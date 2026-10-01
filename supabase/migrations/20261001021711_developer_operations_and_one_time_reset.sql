-- Installation only. This migration NEVER starts or executes a reset.
create table private.platform_reset_control (
  singleton boolean primary key default true check(singleton),
  consumed_at timestamptz,
  keeper_id uuid,
  phase text not null default 'idle' check(phase in ('idle','data','storage','r2','accounts','complete')),
  lease_id uuid,
  lease_until timestamptz,
  last_error text,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
insert into private.platform_reset_control(singleton) values(true);
create table private.platform_reset_tables(table_name text primary key, preserve boolean not null);
-- Snapshot the reviewed schema. Later tables must be reviewed before this one-time operation.
insert into private.platform_reset_tables
select tablename, tablename in ('bible_book_catalog','denominations','policy_documents','app_feature_flags','daily_content_generation_settings')
from pg_tables where schemaname='public';
revoke all on private.platform_reset_control, private.platform_reset_tables from public,anon,authenticated;
alter table private.platform_reset_control enable row level security;
alter table private.platform_reset_tables enable row level security;

create or replace function private.guard_platform_reset_writes()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Auth's account deletion can cascade SET NULL into an already-empty app table.
  -- Signup itself still hits the auth.users guard below.
  if tg_table_schema='public' and session_user='supabase_auth_admin' then return null; end if;
  if current_setting('role')='authenticated' and
    not exists(select 1 from auth.users where id=auth.uid()) then
    raise exception 'Your account is no longer active. Sign in again.' using errcode='42501';
  end if;
  if exists(select 1 from private.platform_reset_control where phase not in ('idle','complete'))
    and not (coalesce(current_setting('grace.reset_worker',true),'')='on'
      and current_setting('role') in ('service_role','postgres','none'))
  then raise exception 'Grace Connect is being reset. Please try again shortly.' using errcode='55000'; end if;
  return null;
end $$;
revoke all on function private.guard_platform_reset_writes() from public,anon,authenticated;

do $$ declare t record; begin
  for t in select table_name from private.platform_reset_tables where table_name<>'developer_accounts' loop
    execute format('create trigger platform_reset_write_guard before insert or update on public.%I for each statement execute function private.guard_platform_reset_writes()',t.table_name);
  end loop;
end $$;
-- Freeze signup/uploads during cleanup, including requests with an old valid session.
create trigger platform_reset_signup_guard before insert on auth.users
for each statement execute function private.guard_platform_reset_writes();
create trigger platform_reset_storage_guard before insert or update on storage.objects
for each statement execute function private.guard_platform_reset_writes();

create or replace function public.platform_reset_begin(p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare state private.platform_reset_control%rowtype;
begin
  select * into state from private.platform_reset_control where singleton for update;
  if state.consumed_at is not null then raise exception 'The one-time reset has already been used.' using errcode='55000'; end if;
  if not exists(select 1 from public.developer_accounts d join auth.users u on u.id=p_actor
    where d.status='active' and d.developer_role='super_developer'
    and (d.user_id=p_actor or (d.user_id is null and lower(d.email)=lower(u.email))))
  then raise exception 'Only the platform owner can reset the app.' using errcode='42501'; end if;
  if not exists(select 1 from public.users where id=p_actor) then raise exception 'The developer profile must exist before resetting.'; end if;
  if exists(select 1 from pg_tables t where t.schemaname='public'
    and not exists(select 1 from private.platform_reset_tables r where r.table_name=t.tablename))
  then raise exception 'The reset inventory needs review because the database schema changed.'; end if;
  update private.platform_reset_control set consumed_at=now(),keeper_id=p_actor,phase='data',updated_at=now() where singleton;
  return jsonb_build_object('accepted',true,'phase','data');
end $$;
revoke all on function public.platform_reset_begin(uuid) from public,anon,authenticated;
grant execute on function public.platform_reset_begin(uuid) to service_role;

create or replace function public.platform_reset_worker(p_command text, p_lease uuid default null, p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare state private.platform_reset_control%rowtype; tables_sql text; keep_user public.users%rowtype; keep_dev public.developer_accounts%rowtype;
begin
  select * into state from private.platform_reset_control where singleton for update;
  if state.phase in ('idle','complete') then return null; end if;
  if p_command='claim' then
    if state.lease_until>now() then return null; end if;
    update private.platform_reset_control set lease_id=gen_random_uuid(),lease_until=now()+interval '90 seconds',updated_at=now()
      where singleton returning * into state;
    return jsonb_build_object('phase',state.phase,'lease',state.lease_id,'keeper_id',state.keeper_id,'consumed_at',state.consumed_at);
  end if;
  if p_lease is null or p_lease is distinct from state.lease_id or state.lease_until<=now() then
    raise exception 'The cleanup lease expired.' using errcode='42501';
  end if;
  if p_command='purge' and state.phase='data' then
    select * into keep_user from public.users where id=state.keeper_id;
    select * into keep_dev from public.developer_accounts
      where status='active' and developer_role='super_developer'
      and (user_id=state.keeper_id or lower(email)=lower(keep_user.email)) limit 1;
    if keep_user.id is null or keep_dev.id is null then raise exception 'Developer preservation check failed.'; end if;
    perform set_config('grace.reset_worker','on',true);
    select string_agg(format('public.%I',table_name),', ' order by table_name)
      into tables_sql from private.platform_reset_tables where not preserve;
    -- No CASCADE: a new cross-schema dependency must fail safely, never erase an unreviewed table.
    execute 'truncate table '||tables_sql;
    insert into public.users(id,uid,email,"fullName","displayName","isDeveloper","accountState",roles,"defaultRole")
      values(keep_user.id,keep_user.id::text,keep_user.email,keep_user."fullName",keep_user."displayName",true,'active',array['Member'],'Member');
    insert into public.developer_accounts(id,user_id,email,developer_role,status,created_at)
      values(keep_dev.id,keep_user.id,keep_dev.email,'super_developer','active',keep_dev.created_at);
    update public.daily_content_generation_settings set updated_by=null;
    update private.platform_reset_control set phase='storage',last_error=null,updated_at=now() where singleton;
    perform set_config('grace.reset_worker','off',true);
  elsif p_command='storage_batch' and state.phase='storage' then
    return (select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'path',name)),'[]'::jsonb)
      from (select bucket_id,name from storage.objects order by bucket_id,name limit 100) o);
  elsif p_command='advance' then
    if state.phase='storage' then
      if exists(select 1 from storage.objects) then raise exception 'Storage cleanup is not finished.'; end if;
      update private.platform_reset_control set phase='r2',updated_at=now() where singleton;
    elsif state.phase='r2' then
      -- Issued reel uploads last 10 minutes; allow a conservative 16-minute drain.
      if state.consumed_at>now()-interval '16 minutes' then
        return jsonb_build_object('waiting_for_uploads',true);
      end if;
      update private.platform_reset_control set phase='accounts',updated_at=now() where singleton;
    elsif state.phase='accounts' then
      if exists(select 1 from auth.users where id<>state.keeper_id) or exists(select 1 from storage.objects) then
        raise exception 'Account or storage cleanup is not finished.';
      end if;
      update private.platform_reset_control set phase='complete',completed_at=now(),updated_at=now(),last_error=null where singleton;
    else raise exception 'Invalid cleanup transition.'; end if;
  elsif p_command='release' then
    update private.platform_reset_control set lease_id=null,lease_until=null,last_error=left(p_error,500),updated_at=now() where singleton;
  else raise exception 'Invalid cleanup command.'; end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.platform_reset_worker(text,uuid,text) from public,anon,authenticated;
grant execute on function public.platform_reset_worker(text,uuid,text) to service_role;

create or replace function public.platform_operations_status(p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare state private.platform_reset_control%rowtype; actor_email text; actor_role text;
begin
  select u.email,d.developer_role into actor_email,actor_role from auth.users u join public.developer_accounts d
    on (d.user_id=u.id or (d.user_id is null and lower(d.email)=lower(u.email)))
    where u.id=p_actor and d.status='active' limit 1;
  if actor_role is null then raise exception 'Developer access required.' using errcode='42501'; end if;
  select * into state from private.platform_reset_control where singleton;
  return jsonb_build_object(
    'checked_at',now(),'role',actor_role,
    'reset',jsonb_build_object('used',state.consumed_at is not null,'phase',state.phase,
      'started_at',state.consumed_at,'completed_at',state.completed_at,'last_error',state.last_error,
      'can_start',actor_role='super_developer' and state.consumed_at is null,
      'preserved_account',actor_email,
      'other_accounts',(select count(*) from auth.users where id<>coalesce(state.keeper_id,p_actor)),
      'churches',(select count(*) from public.churches),
      'storage_objects',(select count(*) from storage.objects)),
    'media_cleanup_pending',(select count(*) from public.media_cleanup_queue),
    'reel_cleanup_pending',(select count(*) from public.reel_media_cleanup_jobs where completed_at is null),
    'reels_pending_review',(select count(*) from public.reels where moderation_status='pending' and deleted_at is null),
    'payment_events',(select count(*) from public.church_billing_events),
    'checkout_sessions',(select count(*) from public.church_checkout_sessions),
    'database_bytes',pg_database_size(current_database()),
    'schedules',(select coalesce(jsonb_agg(jsonb_build_object('name',j.jobname,'active',j.active,
      'last_status',r.status,'last_finished',r.end_time)),'[]'::jsonb)
      from cron.job j left join lateral(select status,end_time from cron.job_run_details where jobid=j.jobid order by runid desc limit 1) r on true
      where j.jobname like 'graceconnect-%'),
    'reset_worker_scheduled',exists(select 1 from cron.job where jobname='graceconnect-one-time-reset-worker' and active)
      and exists(select 1 from vault.decrypted_secrets where name='daily_quiz_cron_secret')
  );
end $$;
revoke all on function public.platform_operations_status(uuid) from public,anon,authenticated;
grant execute on function public.platform_operations_status(uuid) to service_role;

-- Content editing roles only; billing/read-only developers cannot alter app images.
alter policy "developers manage quote backgrounds" on public.quote_backgrounds
using(public.current_developer_role() in ('super_developer','security_admin','content_moderator'))
with check(public.current_developer_role() in ('super_developer','security_admin','content_moderator'));
alter policy "developers write quote backgrounds" on storage.objects
with check(bucket_id='quote-backgrounds' and public.current_developer_role() in ('super_developer','security_admin','content_moderator'));
alter policy "developers update quote backgrounds" on storage.objects
using(bucket_id='quote-backgrounds' and public.current_developer_role() in ('super_developer','security_admin','content_moderator'))
with check(bucket_id='quote-backgrounds' and public.current_developer_role() in ('super_developer','security_admin','content_moderator'));
alter policy "developers delete quote backgrounds" on storage.objects
using(bucket_id='quote-backgrounds' and public.current_developer_role() in ('super_developer','security_admin','content_moderator'));

create or replace function private.audit_quote_background()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' then
    insert into public.media_cleanup_queue(bucket_id,object_path)
      values('quote-backgrounds','quote_backgrounds/'||old.file_name) on conflict do nothing;
  end if;
  if auth.uid() is not null then
    perform public.log_developer_action('quote_background_'||lower(tg_op),'quote_background',
      case when tg_op='DELETE' then old.id::text else new.id::text end,'{}'::jsonb);
  end if;
  return null;
end $$;
revoke all on function private.audit_quote_background() from public,anon,authenticated;
create trigger audit_quote_background after insert or update or delete on public.quote_backgrounds
for each row execute function private.audit_quote_background();

-- Scheduling (the isolated database harness omits only this extension-owned part).
select cron.schedule('graceconnect-one-time-reset-worker','* * * * *',$job$
  select net.http_post(
    url:='https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/developer-platform-operations',
    headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
    body:='{"action":"work"}'::jsonb,timeout_milliseconds:=60000
  ) where exists(select 1 from private.platform_reset_control where phase not in ('idle','complete'));
$job$);
