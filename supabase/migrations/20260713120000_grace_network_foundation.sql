create extension if not exists pgcrypto;

create table if not exists public.app_feature_flags (
  feature_key text primary key,
  enabled boolean not null default false,
  rollout_percent integer not null default 0 check (rollout_percent between 0 and 100),
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.app_feature_flags (feature_key, enabled, rollout_percent)
values
  ('grace_network', true, 100),
  ('grace_rooms', true, 100),
  ('grace_circles', true, 100),
  ('public_profiles', true, 100),
  ('discover_feed', true, 100)
on conflict (feature_key) do update
set enabled = excluded.enabled,
    rollout_percent = excluded.rollout_percent,
    updated_at = now();

alter table public.community_posts
  add column if not exists scope text not null default 'church',
  add column if not exists post_type text not null default 'post',
  add column if not exists origin_church_id text,
  add column if not exists circle_id uuid,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists repost_of uuid,
  add column if not exists is_persistent boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

alter table public.community_posts
  alter column place_id drop not null,
  alter column expires_at drop not null,
  alter column expires_at drop default;

update public.community_posts
set origin_church_id = coalesce(origin_church_id, place_id),
    is_persistent = coalesce(is_persistent, expires_at is null),
    scope = case
      when scope is not null and scope <> '' then scope
      when visible_to_all_churches then 'global'
      else 'church'
    end
where origin_church_id is null
   or scope is null
   or scope = ''
   or is_persistent is null;

create index if not exists community_posts_scope_created_idx
  on public.community_posts (scope, created_at desc);

create index if not exists community_posts_circle_created_idx
  on public.community_posts (circle_id, created_at desc)
  where circle_id is not null;

create index if not exists community_posts_persistent_idx
  on public.community_posts (is_persistent, created_at desc);

create table if not exists public.social_profiles (
  user_id text primary key,
  display_name text not null,
  public_bio text not null default '',
  avatar_url text not null default '',
  church_id text,
  church_name text not null default '',
  visibility text not null default 'public',
  searchable boolean not null default true,
  accepts_messages boolean not null default true,
  follower_count integer not null default 0,
  following_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.social_follows (
  follower_id text not null,
  following_id text not null,
  status text not null default 'accepted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create index if not exists social_follows_following_idx
  on public.social_follows (following_id, status);

create table if not exists public.social_saved_items (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  entity_type text not null,
  entity_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

create table if not exists public.grace_circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  owner_id text not null,
  church_id text,
  visibility text not null default 'public',
  member_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.grace_circle_members (
  circle_id uuid not null references public.grace_circles(id) on delete cascade,
  user_id text not null,
  role text not null default 'member',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  primary key (circle_id, user_id)
);

create table if not exists public.grace_rooms (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  topic text not null default '',
  description text not null default '',
  created_by text not null,
  status text not null default 'open',
  participant_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.grace_room_participants (
  room_id uuid not null references public.grace_rooms(id) on delete cascade,
  user_id text not null,
  anonymous_name text not null,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.grace_room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.grace_rooms(id) on delete cascade,
  author_id text not null,
  anonymous_name text not null,
  body text not null,
  moderation_status text not null default 'visible',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists grace_room_messages_room_created_idx
  on public.grace_room_messages (room_id, created_at);

create table if not exists public.platform_content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id text not null,
  entity_type text not null,
  entity_id text not null,
  reported_user_id text,
  reason text not null default 'other',
  description text not null default '',
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table public.app_feature_flags enable row level security;
alter table public.social_profiles enable row level security;
alter table public.social_follows enable row level security;
alter table public.social_saved_items enable row level security;
alter table public.grace_circles enable row level security;
alter table public.grace_circle_members enable row level security;
alter table public.grace_rooms enable row level security;
alter table public.grace_room_participants enable row level security;
alter table public.grace_room_messages enable row level security;
alter table public.platform_content_reports enable row level security;

drop policy if exists "Authenticated users read enabled feature flags" on public.app_feature_flags;
create policy "Authenticated users read enabled feature flags"
  on public.app_feature_flags for select to authenticated
  using (enabled);

drop policy if exists "Users read public social profiles" on public.social_profiles;
create policy "Users read public social profiles"
  on public.social_profiles for select to authenticated
  using (visibility = 'public' or user_id = auth.uid()::text);

drop policy if exists "Users manage own social profile" on public.social_profiles;
create policy "Users manage own social profile"
  on public.social_profiles for all to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

drop policy if exists "Users read own social follows" on public.social_follows;
create policy "Users read own social follows"
  on public.social_follows for select to authenticated
  using (follower_id = auth.uid()::text or following_id = auth.uid()::text);

drop policy if exists "Users manage follows they start" on public.social_follows;
create policy "Users manage follows they start"
  on public.social_follows for all to authenticated
  using (follower_id = auth.uid()::text)
  with check (follower_id = auth.uid()::text);

drop policy if exists "Users manage own saved items" on public.social_saved_items;
create policy "Users manage own saved items"
  on public.social_saved_items for all to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

drop policy if exists "Authenticated users read public circles" on public.grace_circles;
create policy "Authenticated users read public circles"
  on public.grace_circles for select to authenticated
  using (
    visibility = 'public'
    or owner_id = auth.uid()::text
    or exists (
      select 1 from public.grace_circle_members m
      where m.circle_id = grace_circles.id
        and m.user_id = auth.uid()::text
        and m.status = 'active'
    )
  );

drop policy if exists "Users create own circles" on public.grace_circles;
create policy "Users create own circles"
  on public.grace_circles for insert to authenticated
  with check (owner_id = auth.uid()::text);

drop policy if exists "Circle owners update circles" on public.grace_circles;
create policy "Circle owners update circles"
  on public.grace_circles for update to authenticated
  using (owner_id = auth.uid()::text)
  with check (owner_id = auth.uid()::text);

drop policy if exists "Users read visible circle memberships" on public.grace_circle_members;
create policy "Users read visible circle memberships"
  on public.grace_circle_members for select to authenticated
  using (true);

drop policy if exists "Users manage own circle membership" on public.grace_circle_members;
create policy "Users manage own circle membership"
  on public.grace_circle_members for all to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

drop policy if exists "Authenticated users read open grace rooms" on public.grace_rooms;
create policy "Authenticated users read open grace rooms"
  on public.grace_rooms for select to authenticated
  using (status = 'open' or created_by = auth.uid()::text);

drop policy if exists "Users create grace rooms" on public.grace_rooms;
create policy "Users create grace rooms"
  on public.grace_rooms for insert to authenticated
  with check (created_by = auth.uid()::text);

drop policy if exists "Users manage own room participation" on public.grace_room_participants;
create policy "Users manage own room participation"
  on public.grace_room_participants for all to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

drop policy if exists "Participants read room messages" on public.grace_room_messages;
create policy "Participants read room messages"
  on public.grace_room_messages for select to authenticated
  using (
    moderation_status = 'visible'
    and exists (
      select 1 from public.grace_room_participants p
      where p.room_id = grace_room_messages.room_id
        and p.user_id = auth.uid()::text
    )
  );

drop policy if exists "Participants send room messages" on public.grace_room_messages;
create policy "Participants send room messages"
  on public.grace_room_messages for insert to authenticated
  with check (
    author_id = auth.uid()::text
    and exists (
      select 1 from public.grace_room_participants p
      where p.room_id = grace_room_messages.room_id
        and p.user_id = auth.uid()::text
    )
  );

drop policy if exists "Users create platform reports" on public.platform_content_reports;
create policy "Users create platform reports"
  on public.platform_content_reports for insert to authenticated
  with check (reporter_id = auth.uid()::text);

create or replace function public.refresh_social_counts(target_user_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.social_profiles
  set follower_count = (
        select count(*)::integer
        from public.social_follows
        where following_id = target_user_id and status = 'accepted'
      ),
      following_count = (
        select count(*)::integer
        from public.social_follows
        where follower_id = target_user_id and status = 'accepted'
      ),
      updated_at = now()
  where user_id = target_user_id;
end;
$$;

create or replace function public.request_social_follow(target_user_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
begin
  if actor_id is null or target_user_id is null or actor_id = target_user_id then
    return;
  end if;

  insert into public.social_follows (follower_id, following_id, status)
  values (actor_id, target_user_id, 'accepted')
  on conflict (follower_id, following_id) do update
    set status = 'accepted',
        updated_at = now();

  perform public.refresh_social_counts(actor_id);
  perform public.refresh_social_counts(target_user_id);
end;
$$;

create or replace function public.get_community_feed(
  feed_mode text default 'discover',
  viewer_church_id text default null,
  target_circle_id text default null,
  result_limit integer default 75
)
returns setof public.community_posts
language sql
stable
security definer
set search_path = public
as $$
  select p.*
  from public.community_posts p
  where (p.expires_at is null or p.expires_at > now())
    and (
      case
        when feed_mode = 'church' then
          viewer_church_id is not null and p.place_id = viewer_church_id
        when feed_mode = 'circle' then
          target_circle_id is not null and p.circle_id::text = target_circle_id
        when feed_mode = 'following' then
          p.visible_to_all_churches
          or p.scope in ('global', 'discover', 'public')
          or exists (
            select 1
            from public.social_follows f
            where f.follower_id = auth.uid()::text
              and f.following_id = p.author_id::text
              and f.status = 'accepted'
          )
        else
          p.visible_to_all_churches or p.scope in ('global', 'discover', 'public')
      end
    )
  order by p.created_at desc
  limit greatest(1, least(coalesce(result_limit, 75), 200));
$$;

create or replace function public.create_grace_circle(
  circle_name text,
  circle_description text default '',
  circle_visibility text default 'public'
)
returns public.grace_circles
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  new_circle public.grace_circles;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.grace_circles (name, description, owner_id, visibility, member_count)
  values (circle_name, coalesce(circle_description, ''), actor_id, coalesce(circle_visibility, 'public'), 1)
  returning * into new_circle;

  insert into public.grace_circle_members (circle_id, user_id, role, status)
  values (new_circle.id, actor_id, 'owner', 'active')
  on conflict (circle_id, user_id) do nothing;

  return new_circle;
end;
$$;

create or replace function public.join_grace_circle(target_circle_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.grace_circle_members (circle_id, user_id, status)
  values (target_circle_id, actor_id, 'active')
  on conflict (circle_id, user_id) do update
    set status = 'active';

  update public.grace_circles
  set member_count = (
        select count(*)::integer
        from public.grace_circle_members
        where circle_id = target_circle_id and status = 'active'
      ),
      updated_at = now()
  where id = target_circle_id;
end;
$$;

create or replace function public.list_grace_circles()
returns setof public.grace_circles
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.grace_circles
  where visibility = 'public'
     or owner_id = auth.uid()::text
     or exists (
       select 1 from public.grace_circle_members m
       where m.circle_id = grace_circles.id
         and m.user_id = auth.uid()::text
         and m.status = 'active'
     )
  order by created_at desc
  limit 100;
$$;

create or replace function public.create_grace_room(
  room_title text,
  room_topic text default '',
  room_description text default ''
)
returns public.grace_rooms
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  new_room public.grace_rooms;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.grace_rooms (title, topic, description, created_by, participant_count)
  values (room_title, coalesce(room_topic, ''), coalesce(room_description, ''), actor_id, 1)
  returning * into new_room;

  insert into public.grace_room_participants (room_id, user_id, anonymous_name)
  values (new_room.id, actor_id, 'Anonymous ' || substr(replace(actor_id, '-', ''), 1, 4))
  on conflict (room_id, user_id) do nothing;

  return new_room;
end;
$$;

create or replace function public.join_grace_room(target_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.grace_room_participants (room_id, user_id, anonymous_name, last_seen_at)
  values (target_room_id, actor_id, 'Anonymous ' || substr(replace(actor_id, '-', ''), 1, 4), now())
  on conflict (room_id, user_id) do update
    set last_seen_at = now();

  update public.grace_rooms
  set participant_count = (
        select count(*)::integer
        from public.grace_room_participants
        where room_id = target_room_id
      ),
      updated_at = now()
  where id = target_room_id;
end;
$$;

create or replace function public.list_grace_rooms()
returns setof public.grace_rooms
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.grace_rooms
  where status = 'open'
  order by created_at desc
  limit 100;
$$;

create or replace function public.cleanup_vanishing_content()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_messages integer := 0;
  deleted_posts integer := 0;
  deleted_stories integer := 0;
begin
  delete from public.direct_messages
    where expires_at <= now();
  get diagnostics deleted_messages = row_count;

  delete from public.community_posts
    where expires_at is not null and expires_at <= now();
  get diagnostics deleted_posts = row_count;

  deleted_stories := public.cleanup_expired_community_stories();

  return jsonb_build_object(
    'deleted_messages', deleted_messages,
    'deleted_posts', deleted_posts,
    'deleted_stories', deleted_stories
  );
end;
$$;

grant select on public.app_feature_flags to authenticated;
grant select, insert, update on public.social_profiles to authenticated;
grant select, insert, update, delete on public.social_follows to authenticated;
grant select, insert, delete on public.social_saved_items to authenticated;
grant select, insert, update on public.grace_circles to authenticated;
grant select, insert, update, delete on public.grace_circle_members to authenticated;
grant select, insert, update on public.grace_rooms to authenticated;
grant select, insert, update on public.grace_room_participants to authenticated;
grant select, insert on public.grace_room_messages to authenticated;
grant insert on public.platform_content_reports to authenticated;

grant execute on function public.request_social_follow(text) to authenticated;
grant execute on function public.get_community_feed(text, text, text, integer) to authenticated;
grant execute on function public.create_grace_circle(text, text, text) to authenticated;
grant execute on function public.join_grace_circle(uuid) to authenticated;
grant execute on function public.list_grace_circles() to authenticated;
grant execute on function public.create_grace_room(text, text, text) to authenticated;
grant execute on function public.join_grace_room(uuid) to authenticated;
grant execute on function public.list_grace_rooms() to authenticated;
grant execute on function public.cleanup_vanishing_content() to authenticated;

notify pgrst, 'reload schema';
