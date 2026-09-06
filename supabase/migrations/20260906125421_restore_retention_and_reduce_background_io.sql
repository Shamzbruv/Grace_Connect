-- Restore the owner's 30-day community retention policy for existing clients.
-- Keep media deletion in the Storage API, never DELETE storage.objects directly.
alter table public.community_posts alter column expires_at set default (now() + interval '30 days');

create or replace function public.enforce_community_post_retention()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then new.created_at := old.created_at; end if;
  new.created_at := least(coalesce(new.created_at, now()), now());
  new.expires_at := least(coalesce(new.expires_at, new.created_at + interval '30 days'), new.created_at + interval '30 days');
  new.is_persistent := false;
  return new;
end;
$$;
revoke all on function public.enforce_community_post_retention() from public, anon, authenticated;
create trigger enforce_community_post_retention before insert or update on public.community_posts
for each row execute function public.enforce_community_post_retention();

create table public.media_cleanup_queue (
  bucket_id text not null check (bucket_id in ('community_media', 'chat_media')),
  object_path text not null,
  queued_at timestamptz not null default now(),
  last_error text,
  primary key (bucket_id, object_path)
);
alter table public.media_cleanup_queue enable row level security;
revoke all on public.media_cleanup_queue from public, anon, authenticated;
grant all on public.media_cleanup_queue to service_role;

create or replace function public.retention_media_path(raw_path text, raw_url text, target_bucket text)
returns text language plpgsql immutable set search_path = '' as $$
declare path text := nullif(btrim(raw_path), ''); prefix text;
begin
  if target_bucket not in ('community_media', 'chat_media') then return null; end if;
  if path is null then
    prefix := 'https://nimgsgnkcvddomrgkawb.supabase.co/storage/v1/object/public/' || target_bucket || '/';
    if left(coalesce(raw_url,''), length(prefix)) <> prefix then return null; end if;
    path := replace(split_part(substr(raw_url, length(prefix)+1), '?', 1), '%20', ' ');
  end if;
  -- App-generated names use this alphabet. Unknown encodings are retained.
  if path is null or path !~ '^[a-zA-Z0-9_. /-]+$' or path ~ '(^/|(^|/)\.\.(/|$))' then return null; end if;
  return path;
end;
$$;
revoke all on function public.retention_media_path(text,text,text) from public, anon, authenticated;

create or replace function public.queue_deleted_content_media()
returns trigger language plpgsql security definer set search_path = '' as $$
declare item jsonb := to_jsonb(old); bucket text; path text; thumbnail text;
begin
  bucket := case when tg_table_name='direct_messages' then 'chat_media' else 'community_media' end;
  path := public.retention_media_path(item->>'media_path',item->>'media_url',bucket);
  thumbnail := public.retention_media_path(item->>'media_thumbnail_path',item->>'media_thumbnail_url',bucket);
  insert into public.media_cleanup_queue(bucket_id,object_path)
    select bucket,p from unnest(array[path,thumbnail]) p where p is not null
    on conflict (bucket_id,object_path) do nothing;
  return old;
end;
$$;
revoke all on function public.queue_deleted_content_media() from public, anon, authenticated;
create trigger queue_deleted_post_media after delete on public.community_posts for each row execute function public.queue_deleted_content_media();
create trigger queue_deleted_story_media after delete on public.community_stories for each row execute function public.queue_deleted_content_media();
create trigger queue_deleted_message_media after delete on public.direct_messages for each row execute function public.queue_deleted_content_media();

-- Check all live content plus support/moderation evidence before removing a file.
-- Searching both raw and escaped-space paths conservatively preserves shared media.
create or replace function public.retention_media_is_referenced(target_path text)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_path is null or target_path='' or exists (
    select 1 from (
      select to_jsonb(p)::text as doc from public.community_posts p
      union all select to_jsonb(s)::text from public.community_stories s
      union all select to_jsonb(m)::text from public.direct_messages m
      union all select to_jsonb(t)::text from public.support_tickets t
      union all select to_jsonb(r)::text from public.platform_content_reports r
      union all select to_jsonb(u)::text from public.users u
      union all select to_jsonb(g)::text from public.study_groups g
      union all select to_jsonb(m)::text from public.group_messages m
      union all select to_jsonb(m)::text from public.grace_room_messages m
    ) refs where strpos(doc,target_path)>0 or strpos(doc,replace(target_path,' ','%20'))>0
  );
$$;
revoke all on function public.retention_media_is_referenced(text) from public, anon, authenticated;
grant execute on function public.retention_media_is_referenced(text) to service_role;

create or replace function public.list_retention_media_candidates(batch_size integer default 50)
returns table(bucket_id text,object_path text,bytes bigint)
language sql stable security definer set search_path = '' as $$
  with candidates as (
    select q.bucket_id,q.object_path,coalesce((o.metadata->>'size')::bigint,0) as bytes
    from public.media_cleanup_queue q
    left join storage.objects o on o.bucket_id=q.bucket_id and o.name=q.object_path
    union
    select o.bucket_id,o.name,coalesce((o.metadata->>'size')::bigint,0)
    from storage.objects o
    where o.bucket_id in ('community_media','chat_media')
      and o.created_at<now()-interval '30 days'
      and public.retention_media_path(o.name,null,o.bucket_id) is not null
  )
  select c.bucket_id,c.object_path,c.bytes from candidates c
  where not public.retention_media_is_referenced(c.object_path)
  order by c.bucket_id,c.object_path limit greatest(1,least(batch_size,100));
$$;
revoke all on function public.list_retention_media_candidates(integer) from public, anon, authenticated;
grant execute on function public.list_retention_media_candidates(integer) to service_role;

-- Existing app versions send is_persistent=true and expires_at=null for social
-- posts. The trigger makes those requests obey the same server-side policy.
update public.community_posts set expires_at=least(coalesce(expires_at,created_at+interval '30 days'),created_at+interval '30 days'),is_persistent=false
where is_persistent or expires_at is null or expires_at>created_at+interval '30 days';

create or replace function public.refresh_grace_room_presence(target_room_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare affected integer;
begin
  with counts as (
    select r.id,count(p.user_id)::integer as participants
    from public.grace_rooms r
    left join public.grace_room_participants p on p.room_id=r.id and p.last_seen_at>=now()-interval '2 minutes'
    where target_room_id is null or r.id=target_room_id group by r.id
  )
  update public.grace_rooms r set live_participant_count=c.participants,updated_at=now()
  from counts c where c.id=r.id and r.live_participant_count is distinct from c.participants;
  get diagnostics affected=row_count;
  return affected;
end;
$$;

-- Retain the minute-level check and the existing 26-hour quiz window, but don't
-- start an HTTP/Edge invocation when no expired attempt exists.
create index if not exists quiz_attempts_active_heartbeat_retention_idx
  on public.quiz_attempts(last_heartbeat_at) where status='active';
do $$
declare job record; command_sql text;
begin
  select * into job from cron.job where jobname='daily-bible-quiz-stale-attempt-cleanup';
  if found and job.command not like '%retention_guard_v1%' then
    command_sql := regexp_replace(btrim(job.command), ';\s*$', '') ||
      ' where exists (select 1 from public.quiz_attempts where status=''active'' and last_heartbeat_at<now()-interval ''26 hours'') /* retention_guard_v1 */;';
    perform cron.alter_job(job.jobid,command:=command_sql);
  end if;
end;
$$;

create or replace function public.prune_graceconnect_job_history(batch_size integer default 5000)
returns integer language plpgsql security definer set search_path = '' as $$
declare deleted integer;
begin
  delete from cron.job_run_details where runid in (
    select runid from cron.job_run_details
    where (end_time<now()-interval '7 days' and status='succeeded')
       or (end_time<now()-interval '30 days' and status='failed')
    order by runid limit greatest(1,least(batch_size,5000))
  );
  get diagnostics deleted=row_count;
  return deleted;
end;
$$;
revoke all on function public.prune_graceconnect_job_history(integer) from public, anon, authenticated;
grant execute on function public.prune_graceconnect_job_history(integer) to service_role;
select cron.schedule('graceconnect-job-history-retention','33 * * * *','select public.prune_graceconnect_job_history();');

-- Retention is enforced on the server even when nobody opens the app.
select cron.schedule('graceconnect-hourly-content-retention','12 * * * *','select public.cleanup_vanishing_content();');
select cron.schedule('graceconnect-media-retention','22 * * * *',$job$
  select net.http_post(
    url:='https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/cleanup-retained-media',
    headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
    body:='{}'::jsonb
  );
$job$);
notify pgrst,'reload schema';
