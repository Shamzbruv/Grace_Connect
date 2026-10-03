-- Usage is counted only while the app is active. Per-install cumulative
-- counters make network retries idempotent without a row for every session.
create table public.app_experience_state (
 user_id uuid primary key references auth.users(id) on delete cascade,
 active_seconds bigint not null default 0 check(active_seconds>=0),
 next_prompt_seconds bigint not null default 7200,
 next_prompt_after timestamptz not null default now(),
 prompt_count integer not null default 0,
 response boolean, answered_at timestamptz, last_prompted_at timestamptz,
 last_store_opened_at timestamptz, store_platform text check(store_platform in ('android','ios')),
 resend_requested_at timestamptz, updated_at timestamptz not null default now()
);
create table public.app_experience_devices (
 user_id uuid not null references auth.users(id) on delete cascade,
 device_id uuid not null, active_seconds bigint not null default 0 check(active_seconds>=0),
 updated_at timestamptz not null default now(), primary key(user_id,device_id)
);
create table public.app_experience_events (
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check(kind in ('shown','answered','dismissed','store_opened','resend_requested')),
 response boolean, platform text check(platform in ('android','ios')),
 created_at timestamptz not null default now()
);
create index app_experience_events_user_time on public.app_experience_events(user_id,created_at desc);
create table public.app_review_configuration (
 id boolean primary key default true check(id),
 android_url text not null default 'https://play.google.com/store/apps/details?id=love.graceconnect',
 ios_url text,
 constraint review_android_url check(android_url ~ '^https://play[.]google[.]com/store/apps/details[?]id=[A-Za-z0-9_.]+$'),
 constraint review_ios_url check(ios_url is null or ios_url ~ '^https://apps[.]apple[.]com/([a-z]{2}/)?app/[^?#]*id[0-9]+([?]action=write-review)?$')
);
insert into public.app_review_configuration(id) values(true);
do $$ declare t text; begin
 foreach t in array array['app_experience_state','app_experience_devices','app_experience_events'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('grant all on public.%I to service_role',t);
  execute format('create policy "Read own experience data" on public.%I for select to authenticated using (user_id=(select auth.uid()))',t);
 end loop;
end $$;
alter table public.app_review_configuration enable row level security;
revoke all on public.app_review_configuration from public,anon,authenticated;
grant select on public.app_review_configuration to authenticated;
grant all on public.app_review_configuration to service_role;
create policy "Read review configuration" on public.app_review_configuration for select to authenticated using(true);

-- Definer is intentional: clients may read their records, but cannot rewrite
-- accumulated usage, the prompt cooldown or developer-managed configuration.
-- The actor ALWAYS comes from the verified JWT, never a caller-supplied ID.
create function public.sync_app_experience(p_device_id uuid,p_active_seconds bigint,
 p_action text default 'sync',p_event_id uuid default null,p_response boolean default null,p_platform text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); old_seconds bigint; delta bigint; state public.app_experience_state; can_prompt boolean; claimed boolean:=false; inserted integer:=0;
begin
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_device_id is null or p_active_seconds is null or p_active_seconds not between 0 and 3153600000
  or p_action is null or p_action not in ('sync','shown','answered','dismissed','store_opened')
  or (p_action<>'sync' and (p_event_id is null or p_platform is null or p_platform not in ('android','ios')))
  or (p_action='answered' and p_response is null) then raise exception 'Invalid experience event' using errcode='22023'; end if;
 insert into public.app_experience_state(user_id) values(actor) on conflict do nothing;
 select * into strict state from public.app_experience_state where user_id=actor for update;
 insert into public.app_experience_devices(user_id,device_id) values(actor,p_device_id) on conflict do nothing;
 select active_seconds into old_seconds from public.app_experience_devices where user_id=actor and device_id=p_device_id for update;
 delta:=greatest(0,p_active_seconds-old_seconds);
 if delta>0 then
  update public.app_experience_devices set active_seconds=p_active_seconds,updated_at=now() where user_id=actor and device_id=p_device_id;
  update public.app_experience_state set active_seconds=active_seconds+delta,updated_at=now() where user_id=actor returning * into state;
 end if;
 can_prompt:=state.response is null and state.active_seconds>=state.next_prompt_seconds and now()>=state.next_prompt_after
  and (state.prompt_count<3 or state.resend_requested_at is not null);
 if p_action<>'sync' then
  if p_action='shown' and not can_prompt then return jsonb_build_object('state',to_jsonb(state),'eligible',false,'claimed',false); end if;
  if p_action in ('answered','dismissed') and state.last_prompted_at is null then raise exception 'No survey has been presented'; end if;
  insert into public.app_experience_events(id,user_id,kind,response,platform)
   values(p_event_id,actor,p_action,case when p_action='answered' then p_response end,p_platform) on conflict do nothing;
  get diagnostics inserted=row_count;
  if inserted=1 then
   if p_action='shown' then
    update public.app_experience_state set last_prompted_at=now(),prompt_count=prompt_count+1,
     next_prompt_seconds=active_seconds+7200,next_prompt_after=now()+interval '24 hours',resend_requested_at=null
     where user_id=actor returning * into state; claimed:=true;
   elsif p_action='answered' then
    update public.app_experience_state set response=p_response,answered_at=now() where user_id=actor and response is null returning * into state;
    if not found then select * into state from public.app_experience_state where user_id=actor; end if;
   elsif p_action='store_opened' then
    update public.app_experience_state set last_store_opened_at=now(),store_platform=p_platform where user_id=actor returning * into state;
   end if;
  end if;
 end if;
 return jsonb_build_object('state',to_jsonb(state),'eligible',can_prompt and p_action='sync','claimed',claimed,
  'android_url',(select android_url from public.app_review_configuration where id),
  'ios_url',(select ios_url from public.app_review_configuration where id));
end $$;
revoke all on function public.sync_app_experience(uuid,bigint,text,uuid,boolean,text) from public,anon;
grant execute on function public.sync_app_experience(uuid,bigint,text,uuid,boolean,text) to authenticated;

create function public.developer_app_experience(p_action text default 'list',p_user_id uuid default null,p_limit integer default 50,p_offset integer default 0,p_ios_url text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare role_name text:=public.current_developer_role(); result jsonb; state public.app_experience_state;
begin
 if auth.uid() is null or role_name is null or role_name not in ('super_developer','support_developer','security_admin') then raise exception 'Developer access required' using errcode='42501'; end if;
 if p_action='resend' then
  select * into state from public.app_experience_state where user_id=p_user_id for update;
  if not found or state.response is not null or state.last_prompted_at is null then raise exception 'Only unanswered surveys can be resent'; end if;
  if state.resend_requested_at is null then
   update public.app_experience_state set next_prompt_seconds=greatest(next_prompt_seconds,active_seconds+7200),
    next_prompt_after=greatest(next_prompt_after,now()+interval '24 hours'),resend_requested_at=now() where user_id=p_user_id;
   insert into public.app_experience_events(id,user_id,kind) values(gen_random_uuid(),p_user_id,'resend_requested');
   perform public.log_developer_action('survey_resend','user',p_user_id::text,jsonb_build_object('additional_active_seconds',7200));
  end if;
  return jsonb_build_object('queued',true);
 elsif p_action='configure_ios' then
  if role_name<>'super_developer' then raise exception 'Owner access required' using errcode='42501'; end if;
  update public.app_review_configuration set ios_url=nullif(trim(p_ios_url),'') where id;
  return jsonb_build_object('saved',true);
 elsif p_action<>'list' then raise exception 'Unknown action'; end if;
 select coalesce(jsonb_agg(row),'[]'::jsonb) into result from (
  select s.*,coalesce(nullif(u."fullName",''),u.email,'Member') as display_name,
   greatest(0,s.next_prompt_seconds-s.active_seconds) as remaining_active_seconds,
   'Not available from the store'::text as review_submission_status
  from public.app_experience_state s left join public.users u on u.id=s.user_id
  order by s.updated_at desc,s.user_id limit greatest(1,least(coalesce(p_limit,50),100)) offset greatest(0,coalesce(p_offset,0))
 ) row;
 return jsonb_build_object('entries',result,'total',(select count(*) from public.app_experience_state),
  'configuration',(select to_jsonb(c) from public.app_review_configuration c where id));
end $$;
revoke all on function public.developer_app_experience(text,uuid,integer,integer,text) from public,anon;
grant execute on function public.developer_app_experience(text,uuid,integer,integer,text) to authenticated;

do $$ declare t text; begin
 if to_regclass('private.platform_reset_tables') is not null then
  foreach t in array array['app_experience_state','app_experience_devices','app_experience_events','app_review_configuration'] loop
   insert into private.platform_reset_tables(table_name,preserve) values(t,t='app_review_configuration');
   execute format('create trigger platform_reset_write_guard before insert or update or delete on public.%I for each statement execute function private.guard_platform_reset_writes()',t);
  end loop;
 end if;
end $$;
