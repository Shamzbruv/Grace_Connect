-- Retire Grace Circles and make Grace Room presence represent members who are
-- actually in a room now. This is forward-only and intentionally removes all
-- persisted Grace Circle data when it is applied.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

-- Grace Circle content must not remain discoverable after the feature is
-- removed from the clients.
delete from public.social_saved_items
where entity_type in ('grace_circle', 'grace_circles');

delete from public.notifications
where entity_table in ('grace_circles', 'grace_circle_posts')
   or type in ('circle_invitation', 'circle_post');

delete from public.community_posts
where circle_id is not null
   or scope = 'circle';

-- Prevent direct writes, legacy clients, or privileged jobs from recreating a
-- retired Circle-scoped post after the Circle tables are gone.
alter table public.community_posts
  drop constraint if exists community_posts_scope_not_circle;
alter table public.community_posts
  add constraint community_posts_scope_not_circle
  check (scope <> 'circle');

delete from public.app_feature_flags
where feature_key = 'grace_circles';

drop function if exists public.get_community_feed(text, text, text, integer);
drop function if exists public.get_my_grace_circle_status(uuid);
drop function if exists public.create_grace_circle(text, text, text);
drop function if exists public.join_grace_circle(uuid);
drop function if exists public.list_grace_circles();

-- Remove only the known cross-table policies before dropping the Circle
-- schema. Avoid CASCADE here: an unreviewed production hotfix (for example a
-- view, policy, or foreign key) must make this transaction fail instead of
-- being deleted silently.
drop policy if exists "Authenticated users view visible community posts"
  on public.community_posts;
drop policy if exists "Users create visible community posts"
  on public.community_posts;
drop policy if exists "Authenticated users create visible community comments"
  on public.community_comments;
drop policy if exists "Authenticated users read public circles"
  on public.grace_circles;

alter table public.community_posts
  drop column if exists circle_id;

drop table if exists public.grace_circle_members;
drop table if exists public.grace_circles;

-- Recreate the surviving feed policies without any Circle dependency so
-- ordinary posts remain readable and writable.
create policy "Authenticated users view visible community posts"
  on public.community_posts
  for select
  to authenticated
  using (
    scope <> 'circle'
    and (expires_at is null or expires_at > now())
    and (
      place_id = public.viewer_effective_church_id()
      or visible_to_all_churches
      or scope in ('global', 'discover', 'public')
    )
  );

create policy "Users create visible community posts"
  on public.community_posts
  for insert
  to authenticated
  with check (
    author_id::text = auth.uid()::text
    and scope <> 'circle'
    and (
      visible_to_all_churches
      or scope in ('global', 'discover', 'public')
      or (
        nullif(place_id, '') is not null
        and place_id = public.viewer_effective_church_id()
      )
    )
  );

create policy "Authenticated users create visible community comments"
  on public.community_comments
  for insert
  to authenticated
  with check (
    author_id::text = auth.uid()::text
    and exists (
      select 1
      from public.community_posts p
      where p.id = post_id
        and p.scope <> 'circle'
        and (p.expires_at is null or p.expires_at > now())
        and (
          p.place_id = public.viewer_effective_church_id()
          or p.visible_to_all_churches
          or p.scope in ('global', 'discover', 'public')
        )
    )
  );

-- PL/pgSQL function bodies are not removed when a referenced table is dropped.
-- Replace the like RPC so it cannot call the retired membership table or read
-- the removed circle_id column at runtime.
create or replace function public.toggle_community_post_like(post_id uuid)
returns public.community_posts
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid text := auth.uid()::text;
  current_church_id text := public.viewer_effective_church_id();
  updated_post public.community_posts;
begin
  if current_uid is null or current_uid = '' then
    raise exception 'Not authenticated';
  end if;

  update public.community_posts
    set likes = case
      when coalesce(likes, '[]'::jsonb) ? current_uid
        then coalesce(likes, '[]'::jsonb) - current_uid
      else coalesce(likes, '[]'::jsonb) || jsonb_build_array(current_uid)
    end
    where id = post_id
      and scope <> 'circle'
      and (expires_at is null or expires_at > now())
      and (
        place_id = current_church_id
        or visible_to_all_churches
        or scope in ('global', 'discover', 'public')
      )
    returning * into updated_post;

  if not found then
    raise exception 'Post not found or unavailable';
  end if;

  return updated_post;
end;
$$;

grant execute on function public.toggle_community_post_like(uuid)
to authenticated;

-- The public feed contract no longer accepts a circle target. Following now
-- means followed people only.
create function public.get_community_feed(
  feed_mode text default 'discover',
  viewer_church_id text default null,
  result_limit integer default 75
)
returns setof public.community_posts
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select coalesce(
      nullif(trim(viewer_church_id), ''),
      public.viewer_effective_church_id()
    ) as church_id
  )
  select p.*
  from public.community_posts p
  cross join viewer v
  where (p.expires_at is null or p.expires_at > now())
    and p.scope <> 'circle'
    and (
      case
        when feed_mode = 'church' then
          v.church_id is not null and p.place_id = v.church_id
        when feed_mode = 'following' then
          exists (
            select 1
            from public.social_follows f
            where f.follower_id = auth.uid()::text
              and f.following_id = p.author_id::text
              and f.status = 'accepted'
          )
        else
          p.visible_to_all_churches
          or p.scope in ('global', 'discover', 'public')
      end
    )
  order by p.created_at desc
  limit greatest(1, least(coalesce(result_limit, 75), 200));
$$;

grant execute on function public.get_community_feed(text, text, integer)
to authenticated;

-- Fail the migration instead of leaving a latent production error if a remote
-- hotfix introduced another policy, function, or view that still depends on a
-- removed Circle identifier. Scope-value checks are intentionally allowed;
-- only removed schema identifiers are treated as dangling dependencies.
do $$
declare
  dangling_objects text;
begin
  with function_references as (
    select format(
      'function %I.%I(%s)',
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid)
    ) as object_name
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p')
      and (
        lower(pg_get_functiondef(p.oid)) like '%grace_circle_members%'
        or lower(pg_get_functiondef(p.oid)) like '%grace_circles%'
        or lower(pg_get_functiondef(p.oid)) like '%circle_id%'
      )
  ),
  policy_references as (
    select format(
      'policy %I on %I.%I',
      pol.polname,
      n.nspname,
      c.relname
    ) as object_name
    from pg_policy pol
    join pg_class c on c.oid = pol.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and lower(
        coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') || ' ' ||
        coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '')
      ) ~ '(grace_circle_members|grace_circles|circle_id)'
  ),
  view_references as (
    select format('view %I.%I', schemaname, viewname) as object_name
    from pg_views
    where schemaname = 'public'
      and lower(definition) ~ '(grace_circle_members|grace_circles|circle_id)'
    union all
    select format('materialized view %I.%I', schemaname, matviewname)
    from pg_matviews
    where schemaname = 'public'
      and lower(definition) ~ '(grace_circle_members|grace_circles|circle_id)'
  ),
  all_references as (
    select object_name from function_references
    union all
    select object_name from policy_references
    union all
    select object_name from view_references
  )
  select string_agg(object_name, ', ' order by object_name)
    into dangling_objects
  from all_references;

  if dangling_objects is not null then
    raise exception
      'Grace Circle retirement left dangling database references: %',
      dangling_objects;
  end if;
end;
$$;

alter table public.grace_rooms
  add column if not exists live_participant_count integer not null default 0
    check (live_participant_count >= 0);

create index if not exists grace_room_participants_live_idx
  on public.grace_room_participants (room_id, last_seen_at desc);

-- A member remains live while heartbeats arrive. Two minutes allows a brief
-- background/network interruption without leaving a ghost count indefinitely.
create or replace function public.refresh_grace_room_presence(
  target_room_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer := 0;
begin
  update public.grace_rooms room
  set live_participant_count = (
        select count(*)::integer
        from public.grace_room_participants participant
        where participant.room_id = room.id
          and participant.last_seen_at >= now() - interval '2 minutes'
      ),
      updated_at = case
        when room.live_participant_count is distinct from (
          select count(*)::integer
          from public.grace_room_participants participant
          where participant.room_id = room.id
            and participant.last_seen_at >= now() - interval '2 minutes'
        ) then now()
        else room.updated_at
      end
  where target_room_id is null or room.id = target_room_id;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function public.touch_grace_room_presence(target_room_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  live_count integer;
begin
  if actor_id is null or actor_id = '' then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.grace_rooms
    where id = target_room_id
      and is_platform_room
      and status = 'open'
  ) then
    raise exception 'Grace Room is not available';
  end if;

  insert into public.grace_room_participants (
    room_id,
    user_id,
    anonymous_name,
    last_seen_at
  )
  values (
    target_room_id,
    actor_id,
    public.grace_room_anonymous_name(target_room_id, actor_id),
    now()
  )
  on conflict (room_id, user_id) do update
    set last_seen_at = excluded.last_seen_at,
        anonymous_name = excluded.anonymous_name;

  update public.grace_rooms
  set participant_count = (
        select count(*)::integer
        from public.grace_room_participants
        where room_id = target_room_id
      )
  where id = target_room_id;

  perform public.refresh_grace_room_presence(target_room_id);

  select live_participant_count
    into live_count
  from public.grace_rooms
  where id = target_room_id;

  return coalesce(live_count, 0);
end;
$$;

create or replace function public.leave_grace_room(target_room_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  live_count integer;
begin
  if actor_id is null or actor_id = '' then
    raise exception 'Not authenticated';
  end if;

  -- Keep the participant row so returning members retain their stable anonymous
  -- name and message access, but expire its live heartbeat immediately.
  update public.grace_room_participants
  set last_seen_at = to_timestamp(0)
  where room_id = target_room_id
    and user_id = actor_id;

  perform public.refresh_grace_room_presence(target_room_id);

  select live_participant_count
    into live_count
  from public.grace_rooms
  where id = target_room_id;

  return coalesce(live_count, 0);
end;
$$;

create or replace function public.join_grace_room(target_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.touch_grace_room_presence(target_room_id);
end;
$$;

grant execute on function public.touch_grace_room_presence(uuid)
to authenticated;
grant execute on function public.leave_grace_room(uuid)
to authenticated;
grant execute on function public.join_grace_room(uuid)
to authenticated;

revoke all on function public.refresh_grace_room_presence(uuid)
from public, anon, authenticated;
grant execute on function public.refresh_grace_room_presence(uuid)
to service_role;

alter table public.grace_rooms replica identity full;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'grace_rooms'
  ) then
    execute 'alter publication supabase_realtime add table public.grace_rooms';
  end if;
exception when undefined_object then
  null;
end;
$$;

do $$
begin
  if exists (
    select 1 from cron.job where jobname = 'refresh-grace-room-presence'
  ) then
    perform cron.unschedule('refresh-grace-room-presence');
  end if;
end;
$$;

select cron.schedule(
  'refresh-grace-room-presence',
  '* * * * *',
  'select public.refresh_grace_room_presence(null);'
);

-- Each scheduled invitation claims a unique Jamaica-local day/slot before any
-- delivery work. Retries therefore cannot send the same invitation twice.
create table if not exists public.grace_room_invitation_runs (
  id uuid primary key default gen_random_uuid(),
  invitation_date date not null,
  invitation_slot text not null,
  room_id uuid references public.grace_rooms(id) on delete set null,
  in_app_count integer not null default 0,
  in_app_created_at timestamptz,
  push_sent boolean not null default false,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_attempt_at timestamptz,
  provider_error text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (invitation_date, invitation_slot)
);

alter table public.grace_room_invitation_runs
  add column if not exists in_app_created_at timestamptz,
  add column if not exists attempt_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz;

alter table public.grace_room_invitation_runs enable row level security;
revoke all on public.grace_room_invitation_runs from public, anon, authenticated;
grant all on public.grace_room_invitation_runs to service_role;

create unique index if not exists
  notifications_one_grace_room_invitation_per_run_user_idx
on public.notifications (user_id, type, entity_id)
where type = 'grace_room_invitation'
  and entity_table = 'grace_room_invitation_runs';

-- Claim the first attempt or reclaim a failed/stale lease. Successful runs
-- never become claimable again, while a crashed invocation can be retried by
-- the second same-evening cron without creating duplicate in-app rows.
create or replace function public.claim_grace_room_invitation_run(
  p_invitation_date date,
  p_invitation_slot text,
  p_room_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  claimed public.grace_room_invitation_runs%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required.';
  end if;

  if p_invitation_date is null
      or nullif(trim(coalesce(p_invitation_slot, '')), '') is null
      or p_room_id is null then
    raise exception 'Invitation date, slot, and room are required.';
  end if;

  insert into public.grace_room_invitation_runs as invitation_run (
    invitation_date,
    invitation_slot,
    room_id,
    attempt_count,
    last_attempt_at,
    provider_error,
    completed_at
  ) values (
    p_invitation_date,
    trim(p_invitation_slot),
    p_room_id,
    1,
    now(),
    null,
    null
  )
  on conflict (invitation_date, invitation_slot) do update
    set room_id = coalesce(invitation_run.room_id, excluded.room_id),
        attempt_count = invitation_run.attempt_count + 1,
        last_attempt_at = now(),
        provider_error = null,
        completed_at = null
    where invitation_run.push_sent = false
      and (
        invitation_run.last_attempt_at is null
        or invitation_run.last_attempt_at < now() - interval '10 minutes'
      )
  returning * into claimed;

  if claimed.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'id', claimed.id,
    'room_id', claimed.room_id,
    'attempt_count', claimed.attempt_count,
    'should_create_in_app', claimed.in_app_created_at is null,
    'in_app_count', claimed.in_app_count
  );
end;
$$;

revoke all on function public.claim_grace_room_invitation_run(
  date, text, uuid
) from public, anon, authenticated;
grant execute on function public.claim_grace_room_invitation_run(
  date, text, uuid
) to service_role;

-- Notification creation and its completion marker share one transaction. A
-- retry after an invocation crash therefore sees either all intended rows or
-- none, and the partial unique index is a final duplicate-delivery guard.
create or replace function public.create_grace_room_invitation_notifications(
  p_run_id uuid,
  p_title text,
  p_body text,
  p_route text
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  invitation_run public.grace_room_invitation_runs%rowtype;
  notification_count integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required.';
  end if;

  select * into invitation_run
  from public.grace_room_invitation_runs
  where id = p_run_id
  for update;

  if not found then
    raise exception 'Invitation run not found.';
  end if;

  if invitation_run.in_app_created_at is not null then
    return invitation_run.in_app_count;
  end if;

  insert into public.notifications (
    user_id,
    actor_id,
    actor_name,
    type,
    title,
    body,
    place_id,
    entity_table,
    entity_id,
    route
  )
  select
    member.id,
    null,
    'Grace Connect',
    'grace_room_invitation',
    p_title,
    p_body,
    null,
    'grace_room_invitation_runs',
    invitation_run.id::text,
    p_route
  from public.users member
  where member.id is not null
  on conflict (user_id, type, entity_id)
    where type = 'grace_room_invitation'
      and entity_table = 'grace_room_invitation_runs'
  do nothing;

  select count(*)::integer
    into notification_count
  from public.notifications notification
  where notification.type = 'grace_room_invitation'
    and notification.entity_table = 'grace_room_invitation_runs'
    and notification.entity_id = invitation_run.id::text;

  update public.grace_room_invitation_runs
     set in_app_count = notification_count,
         in_app_created_at = now()
   where id = invitation_run.id;

  return notification_count;
end;
$$;

revoke all on function public.create_grace_room_invitation_notifications(
  uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_grace_room_invitation_notifications(
  uuid, text, text, text
) to service_role;

do $$
begin
  if exists (
    select 1 from cron.job where jobname = 'grace-room-support-invitations'
  ) then
    perform cron.unschedule('grace-room-support-invitations');
  end if;
end;
$$;

-- 00:30/00:45 UTC on Monday, Wednesday, and Friday is 7:30/7:45 PM in
-- Jamaica on Sunday, Tuesday, and Thursday. The second run is a retry window;
-- the atomic claim makes it a no-op after a successful first delivery.
select cron.schedule(
  'grace-room-support-invitations',
  '30,45 0 * * 1,3,5',
  $cron$
  select net.http_post(
    url := coalesce(
      (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'grace_connect_project_url'
        limit 1
      ),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/send-grace-room-invitations',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'daily_quiz_cron_secret'
          limit 1
        ),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $cron$
);

select public.refresh_grace_room_presence(null);
select pg_notify('pgrst', 'reload schema');
