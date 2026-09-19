-- Reel media lifecycle: deletion, orphan cleanup, and a retry queue.
--
-- The failure that matters here is silent orphaning. A device can abandon an
-- upload after the bytes land in R2 but before publish, and an R2 delete can
-- fail transiently. Either way nothing in Postgres would point at the object
-- again, so it would be billed and stored forever with no way to find it.
-- Every object therefore gets a durable row describing work still owed.

create table if not exists public.reel_media_cleanup_jobs (
  id uuid primary key default gen_random_uuid(),
  object_key text not null,
  reason text not null,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint reel_cleanup_reason_check
    check (reason in ('deleted_reel','expired_session','failed_upload'))
);

-- One outstanding job per object; a retry must not fan out into duplicates.
create unique index if not exists reel_media_cleanup_pending_key
  on public.reel_media_cleanup_jobs (object_key) where completed_at is null;
create index if not exists reel_media_cleanup_due_idx
  on public.reel_media_cleanup_jobs (next_attempt_at) where completed_at is null;

alter table public.reel_media_cleanup_jobs enable row level security;
-- Server-owned entirely. No client reads or writes this.
revoke all on public.reel_media_cleanup_jobs from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Deletion. Idempotent: deleting an already-deleted reel succeeds rather than
-- erroring, so a client retry after a dropped response is safe.
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_reel(p_reel_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  target public.reels%rowtype;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  select * into target from public.reels where id = p_reel_id;
  if not found then
    -- Already gone. Report success so a retry is not an error.
    return jsonb_build_object('deleted', true, 'already_deleted', true, 'object_keys', '[]'::jsonb);
  end if;
  if target.author_id <> actor::text then
    raise exception 'Only the author can delete this reel.' using errcode = '42501';
  end if;
  if target.deleted_at is not null then
    return jsonb_build_object('deleted', true, 'already_deleted', true, 'object_keys', '[]'::jsonb);
  end if;

  -- Hide it immediately; the bytes are removed by the caller and, if that
  -- fails, by the retry queue.
  update public.reels
     set deleted_at = now(), status = 'deleted', updated_at = now()
   where id = p_reel_id;

  insert into public.reel_media_cleanup_jobs (object_key, reason)
  select key, 'deleted_reel'
  from unnest(array_remove(array[target.video_object_key, target.poster_object_key], null)) key
  on conflict (object_key) where completed_at is null do nothing;

  return jsonb_build_object(
    'deleted', true,
    'already_deleted', false,
    'object_keys', to_jsonb(array_remove(array[target.video_object_key, target.poster_object_key], null))
  );
end;
$$;
revoke all on function public.delete_my_reel(uuid) from public, anon;
grant execute on function public.delete_my_reel(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Orphan sweep. Expired, never-completed sessions surrender their objects to
-- the cleanup queue, and the half-created reel row goes with them.
-- ---------------------------------------------------------------------------
create or replace function public.expire_reel_upload_sessions()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  expired_count integer := 0;
begin
  with stale as (
    select * from public.reel_upload_sessions
    where status in ('pending','uploaded')
      and expires_at < now()
  ), queued as (
    insert into public.reel_media_cleanup_jobs (object_key, reason)
    select key, 'expired_session'
    from stale, unnest(array_remove(array[stale.video_object_key, stale.poster_object_key], null)) key
    on conflict (object_key) where completed_at is null do nothing
    returning 1
  ), marked as (
    update public.reel_upload_sessions s set status = 'expired'
    from stale where s.id = stale.id
    returning 1
  )
  select count(*) into expired_count from stale;

  -- A reel that never published has no life outside its session.
  delete from public.reels r
  where r.status = 'uploading'
    and r.published_at is null
    and exists (
      select 1 from public.reel_upload_sessions s
      where s.reel_id = r.id and s.status = 'expired'
    );
  return expired_count;
end;
$$;
revoke all on function public.expire_reel_upload_sessions() from public, anon, authenticated;
grant execute on function public.expire_reel_upload_sessions() to service_role;

create or replace function public.claim_reel_cleanup_jobs(p_limit integer default 50)
returns table (id uuid, object_key text, attempts integer)
language sql security definer set search_path = ''
as $$
  update public.reel_media_cleanup_jobs j
     set attempts = j.attempts + 1,
         -- Back off so a persistently failing object does not spin every run.
         next_attempt_at = now() + make_interval(mins => least(60, greatest(1, j.attempts * 5)))
   where j.id in (
     select c.id from public.reel_media_cleanup_jobs c
     where c.completed_at is null and c.next_attempt_at <= now()
     order by c.next_attempt_at
     limit greatest(1, least(coalesce(p_limit, 50), 200))
     for update skip locked
   )
  returning j.id, j.object_key, j.attempts;
$$;
revoke all on function public.claim_reel_cleanup_jobs(integer) from public, anon, authenticated;
grant execute on function public.claim_reel_cleanup_jobs(integer) to service_role;

create or replace function public.complete_reel_cleanup_job(p_id uuid, p_error text default null)
returns void language sql security definer set search_path = ''
as $$
  update public.reel_media_cleanup_jobs
     set completed_at = case when p_error is null then now() else null end,
         last_error = p_error
   where id = p_id;
$$;
revoke all on function public.complete_reel_cleanup_job(uuid, text) from public, anon, authenticated;
grant execute on function public.complete_reel_cleanup_job(uuid, text) to service_role;

-- Hourly sweep, matching the existing media-retention convention.
select cron.unschedule('graceconnect-reel-upload-cleanup')
  where exists (select 1 from cron.job where jobname = 'graceconnect-reel-upload-cleanup');
select cron.schedule('graceconnect-reel-upload-cleanup','37 * * * *',$job$
  select net.http_post(
    url:='https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/cleanup-reel-uploads',
    headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
    body:='{}'::jsonb,
    timeout_milliseconds:=60000
  );
$job$);
