create extension if not exists pgcrypto;

alter table public.churches
  add column if not exists live_is_public boolean not null default false;

alter table public.grace_circles
  add column if not exists join_mode text not null default 'approval';

update public.grace_circles
set join_mode = 'approval'
where nullif(trim(coalesce(join_mode, '')), '') is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'grace_circles_join_mode_check'
      and conrelid = 'public.grace_circles'::regclass
  ) then
    alter table public.grace_circles
      add constraint grace_circles_join_mode_check
      check (join_mode in ('open', 'approval'));
  end if;
end $$;

create or replace function public.viewer_effective_church_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(public.current_active_church_id(), ''),
    (
      select nullif(u."placeId", '')
      from public.users u
      where u.id = auth.uid()
         or u.uid = auth.uid()::text
      order by u."joinDate" desc nulls last
      limit 1
    )
  );
$$;

create or replace function public.grace_connect_global_church_id()
returns text
language sql
immutable
as $$
  select 'grace_connect_global'::text;
$$;

create or replace function public.grace_connect_leaderboard_church_id()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(public.viewer_effective_church_id(), ''),
    public.grace_connect_global_church_id()
  );
$$;

create or replace function public.upsert_social_profile_from_user_row()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id text := coalesce(nullif(new.uid, ''), new.id::text);
  v_display_name text := coalesce(
    nullif(trim(new."fullName"), ''),
    nullif(trim(new.email), ''),
    'Grace Connect Member'
  );
begin
  insert into public.social_profiles (
    user_id,
    display_name,
    avatar_url,
    church_id,
    church_name,
    visibility,
    searchable,
    accepts_messages,
    updated_at
  )
  values (
    v_user_id,
    v_display_name,
    coalesce(new."photoUrl", ''),
    nullif(new."placeId", ''),
    coalesce(new."placeName", ''),
    case when coalesce(new."isProfilePrivate", false) then 'private' else 'public' end,
    not coalesce(new."isProfilePrivate", false),
    coalesce(new."allowMessages", true),
    now()
  )
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        avatar_url = case
          when nullif(excluded.avatar_url, '') is null
            then public.social_profiles.avatar_url
          else excluded.avatar_url
        end,
        church_id = excluded.church_id,
        church_name = excluded.church_name,
        visibility = excluded.visibility,
        searchable = excluded.searchable,
        accepts_messages = excluded.accepts_messages,
        updated_at = now();

  return new;
end;
$$;

insert into public.social_profiles (
  user_id,
  display_name,
  avatar_url,
  church_id,
  church_name,
  visibility,
  searchable,
  accepts_messages,
  updated_at
)
select
  coalesce(nullif(u.uid, ''), u.id::text),
  coalesce(nullif(trim(u."fullName"), ''), nullif(trim(u.email), ''), 'Grace Connect Member'),
  coalesce(u."photoUrl", ''),
  nullif(u."placeId", ''),
  coalesce(u."placeName", ''),
  case when coalesce(u."isProfilePrivate", false) then 'private' else 'public' end,
  not coalesce(u."isProfilePrivate", false),
  coalesce(u."allowMessages", true),
  now()
from public.users u
where coalesce(nullif(u.uid, ''), u.id::text) is not null
on conflict (user_id) do update
  set display_name = excluded.display_name,
      avatar_url = case
        when nullif(excluded.avatar_url, '') is null
          then public.social_profiles.avatar_url
        else excluded.avatar_url
      end,
      church_id = excluded.church_id,
      church_name = excluded.church_name,
      visibility = excluded.visibility,
      searchable = excluded.searchable,
      accepts_messages = excluded.accepts_messages,
      updated_at = now();

drop trigger if exists sync_social_profile_from_user_row on public.users;
create trigger sync_social_profile_from_user_row
  after insert or update of
    uid,
    email,
    "fullName",
    "photoUrl",
    "placeId",
    "placeName",
    "allowMessages",
    "isProfilePrivate"
  on public.users
  for each row execute function public.upsert_social_profile_from_user_row();

drop policy if exists "Members view own or shared community posts"
  on public.community_posts;
drop policy if exists "Authenticated users view active community posts"
  on public.community_posts;
create policy "Authenticated users view visible community posts"
  on public.community_posts
  for select
  to authenticated
  using (
    (expires_at is null or expires_at > now())
    and (
      place_id = public.viewer_effective_church_id()
      or visible_to_all_churches
      or scope in ('global', 'discover', 'public')
      or (
        scope = 'circle'
        and circle_id is not null
        and exists (
          select 1
          from public.grace_circle_members m
          where m.circle_id = community_posts.circle_id
            and m.user_id = auth.uid()::text
            and m.status = 'active'
        )
      )
    )
  );

drop policy if exists "Users create visible community posts"
  on public.community_posts;
create policy "Users create visible community posts"
  on public.community_posts
  for insert
  to authenticated
  with check (
    author_id::text = auth.uid()::text
    and (
      visible_to_all_churches
      or scope in ('global', 'discover', 'public')
      or (
        nullif(place_id, '') is not null
        and place_id = public.viewer_effective_church_id()
      )
      or (
        scope = 'circle'
        and circle_id is not null
        and exists (
          select 1
          from public.grace_circle_members m
          where m.circle_id = community_posts.circle_id
            and m.user_id = auth.uid()::text
            and m.status = 'active'
        )
      )
    )
  );

drop policy if exists "Members create community comments"
  on public.community_comments;
drop policy if exists "Active members create community comments"
  on public.community_comments;
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
        and (p.expires_at is null or p.expires_at > now())
        and (
          p.place_id = public.viewer_effective_church_id()
          or p.visible_to_all_churches
          or p.scope in ('global', 'discover', 'public')
          or (
            p.scope = 'circle'
            and p.circle_id is not null
            and exists (
              select 1
              from public.grace_circle_members m
              where m.circle_id = p.circle_id
                and m.user_id = auth.uid()::text
                and m.status = 'active'
            )
          )
        )
    )
  );

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
      and (expires_at is null or expires_at > now())
      and (
        place_id = current_church_id
        or visible_to_all_churches
        or scope in ('global', 'discover', 'public')
        or (
          scope = 'circle'
          and circle_id is not null
          and exists (
            select 1
            from public.grace_circle_members m
            where m.circle_id = community_posts.circle_id
              and m.user_id = current_uid
              and m.status = 'active'
          )
        )
      )
    returning * into updated_post;

  if not found then
    raise exception 'Post not found or unavailable';
  end if;

  return updated_post;
end;
$$;

create or replace function public.toggle_community_story_like(target_story_id uuid)
returns public.community_stories
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  current_church_id text := public.viewer_effective_church_id();
  updated_story public.community_stories;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  update public.community_stories
    set likes = case
      when actor_uid = any(coalesce(likes, '{}'::text[]))
        then array_remove(coalesce(likes, '{}'::text[]), actor_uid)
      else array_append(coalesce(likes, '{}'::text[]), actor_uid)
    end
    where id = target_story_id
      and expires_at > now()
      and (
        church_id = current_church_id
        or visible_to_all_churches
      )
    returning * into updated_story;

  if updated_story.id is null then
    raise exception 'Status not found';
  end if;

  return updated_story;
end;
$$;

drop policy if exists "Members create direct conversations"
  on public.direct_conversations;
create policy "Members create direct conversations"
  on public.direct_conversations
  for insert
  to authenticated
  with check (
    created_by = auth.uid()::text
    and auth.uid()::text = any(member_ids)
    and array_length(member_ids, 1) = 2
    and not exists (
      select 1
      from public.user_blocks b
      where (b.blocker_id = member_ids[1] and b.blocked_user_id = member_ids[2])
         or (b.blocker_id = member_ids[2] and b.blocked_user_id = member_ids[1])
    )
  );

create or replace function public.get_or_create_direct_conversation(
  other_user_id text
)
returns public.direct_conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  clean_other_user_id text := nullif(trim(other_user_id), '');
  actor_church_id text := public.viewer_effective_church_id();
  other_member public.users%rowtype;
  other_uid text;
  other_auth_id text;
  other_lookup_ids text[];
  other_is_same_church boolean := false;
  conversation_church_id text;
  conversation_key text;
  lookup_keys text[];
  existing_conversation public.direct_conversations;
  new_conversation public.direct_conversations;
  has_message_grant boolean := false;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  if clean_other_user_id is null then
    raise exception 'Select a member to message';
  end if;

  if clean_other_user_id = actor_uid then
    raise exception 'You cannot message yourself';
  end if;

  select *
    into other_member
    from public.users u
    where u.uid = clean_other_user_id
       or u.id::text = clean_other_user_id
    limit 1;

  if other_member.id is null then
    raise exception 'That public profile was not found.';
  end if;

  other_auth_id := other_member.id::text;
  other_uid := coalesce(nullif(other_member.uid, ''), other_auth_id);

  if other_uid = actor_uid or other_auth_id = actor_uid then
    raise exception 'You cannot message yourself';
  end if;

  select array_agg(distinct value)
    into other_lookup_ids
    from unnest(array[other_uid, other_auth_id, clean_other_user_id]) as value
    where value is not null and value <> '';

  other_is_same_church :=
    actor_church_id is not null
    and actor_church_id <> ''
    and coalesce(other_member."placeId", '') = actor_church_id;

  conversation_key := public.direct_message_participant_key(
    actor_uid,
    other_uid
  );

  insert into public.direct_message_grants (
    participant_key,
    user_a,
    user_b,
    source_type,
    source_id,
    granted_by,
    created_at,
    revoked_at
  )
  select
    conversation_key,
    least(actor_uid, other_uid),
    greatest(actor_uid, other_uid),
    'bible_nudge',
    n.id,
    n.recipient_id::text,
    coalesce(n.responded_at, n.created_at, now()),
    null
  from public.bible_nudges n
  where n.status = 'accepted'
    and (
      (n.sender_id::text = actor_uid and n.recipient_id::text = any(other_lookup_ids))
      or
      (n.recipient_id::text = actor_uid and n.sender_id::text = any(other_lookup_ids))
    )
  order by n.responded_at desc nulls last, n.created_at desc
  limit 1
  on conflict (participant_key) do update
    set revoked_at = null,
        source_type = 'bible_nudge',
        source_id = coalesce(public.direct_message_grants.source_id, excluded.source_id),
        granted_by = coalesce(public.direct_message_grants.granted_by, excluded.granted_by);

  has_message_grant := public.has_direct_message_grant(actor_uid, other_uid)
    or public.has_direct_message_grant(actor_uid, other_auth_id)
    or public.has_direct_message_grant(actor_uid, clean_other_user_id);

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = actor_uid and b.blocked_user_id = any(other_lookup_ids))
       or (b.blocker_id = any(other_lookup_ids) and b.blocked_user_id = actor_uid)
  ) then
    raise exception 'Messages are not available with this member';
  end if;

  select array_agg(distinct key_value)
    into lookup_keys
    from unnest(array[
      conversation_key,
      public.direct_message_participant_key(actor_uid, other_auth_id),
      public.direct_message_participant_key(actor_uid, clean_other_user_id)
    ]) as key_value
    where key_value is not null and key_value <> '';

  select *
    into existing_conversation
    from public.direct_conversations
    where participant_key = any(lookup_keys)
    order by created_at desc
    limit 1;

  if existing_conversation.id is not null then
    update public.direct_conversations
      set hidden_for = array_remove(
        array_remove(
          array_remove(coalesce(hidden_for, '{}'::text[]), actor_uid),
          other_uid
        ),
        other_auth_id
      )
      where id = existing_conversation.id
      returning * into existing_conversation;

    return existing_conversation;
  end if;

  if not other_is_same_church
      and not has_message_grant
      and not coalesce(other_member."allowMessages", true) then
    raise exception 'This member is not accepting messages right now';
  end if;

  conversation_church_id := coalesce(
    nullif(actor_church_id, ''),
    nullif(other_member."placeId", ''),
    'public'
  );

  insert into public.direct_conversations (
    church_id,
    member_ids,
    participant_key,
    created_by,
    last_message_at
  )
  values (
    conversation_church_id,
    array[actor_uid, other_uid],
    conversation_key,
    actor_uid,
    now()
  )
  returning * into new_conversation;

  return new_conversation;
end;
$$;

create or replace function public.is_live_stream_church_member(p_church_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.church_memberships cm
    join public.churches c
      on c.id = cm.church_id
      or c."placeId" = cm.church_id
    where cm.user_id = auth.uid()
      and cm.membership_status = 'active'
      and (cm.church_id = p_church_id or c.id = p_church_id or c."placeId" = p_church_id)
      and coalesce(c.church_status, 'approved') = 'approved'
      and coalesce(c.public_visibility, true)
  )
  or exists (
    select 1
    from public.users u
    where (u.id = auth.uid() or u.uid = auth.uid()::text)
      and nullif(u."placeId", '') = p_church_id
  );
$$;

create or replace function public.is_live_stream_visible_to_viewer(p_church_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_live_stream_church_member(p_church_id)
    or exists (
      select 1
      from public.churches c
      where (c.id = p_church_id or c."placeId" = p_church_id)
        and coalesce(c."isLive", false)
        and nullif(trim(coalesce(c."liveStreamUrl", '')), '') is not null
        and coalesce(c.live_is_public, false)
        and coalesce(c.church_status, 'approved') = 'approved'
        and coalesce(c.public_visibility, true)
    );
$$;

create or replace function public.list_visible_live_churches(
  viewer_church_id text default null,
  result_limit integer default 30
)
returns setof public.churches
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    select coalesce(
      nullif(trim(viewer_church_id), ''),
      nullif(public.viewer_effective_church_id(), '')
    ) as church_id
  )
  select c.*
  from public.churches c
  cross join viewer v
  where coalesce(c."isLive", false)
    and nullif(trim(coalesce(c."liveStreamUrl", '')), '') is not null
    and coalesce(c.church_status, 'approved') = 'approved'
    and coalesce(c.public_visibility, true)
    and (
      coalesce(c.live_is_public, false)
      or (v.church_id is not null and (c.id = v.church_id or c."placeId" = v.church_id))
    )
  order by
    case
      when v.church_id is not null and (c.id = v.church_id or c."placeId" = v.church_id)
        then 0
      else 1
    end,
    c.name asc
  limit greatest(1, least(coalesce(result_limit, 30), 100));
$$;

drop policy if exists "Members manage their own live stream heartbeat"
  on public.live_stream_viewers;
create policy "Members manage their own live stream heartbeat"
  on public.live_stream_viewers
  for all
  to authenticated
  using (user_id = auth.uid()::text)
  with check (
    user_id = auth.uid()::text
    and public.is_live_stream_visible_to_viewer(church_id)
  );

create or replace function public.record_live_stream_viewer_heartbeat(
  p_church_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id text := trim(coalesce(p_church_id, ''));
  v_user_id text := auth.uid()::text;
begin
  if v_user_id is null or v_user_id = '' then
    raise exception 'Authentication required.';
  end if;

  if v_church_id = '' or not public.is_live_stream_visible_to_viewer(v_church_id) then
    raise exception 'Live stream is not available.';
  end if;

  insert into public.live_stream_viewers (
    church_id,
    user_id,
    last_seen_at,
    is_active,
    updated_at
  )
  values (
    v_church_id,
    v_user_id,
    now(),
    true,
    now()
  )
  on conflict (church_id, user_id)
  do update set
    last_seen_at = excluded.last_seen_at,
    is_active = true,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function public.get_live_stream_viewer_count(
  p_church_id text
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_church_id text := trim(coalesce(p_church_id, ''));
  v_count integer := 0;
begin
  if auth.uid() is null then
    return 0;
  end if;

  if v_church_id = '' or not public.is_live_stream_visible_to_viewer(v_church_id) then
    return 0;
  end if;

  select count(*)::integer
  into v_count
  from public.live_stream_viewers
  where church_id = v_church_id
    and is_active = true
    and last_seen_at >= now() - interval '90 seconds';

  return coalesce(v_count, 0);
end;
$$;

drop policy if exists "Church members view bible streaks"
  on public.bible_streaks;
create policy "Church members view bible streaks"
  on public.bible_streaks
  for select
  to authenticated
  using (church_id = public.grace_connect_leaderboard_church_id());

drop policy if exists "Members upsert own bible streak"
  on public.bible_streaks;
create policy "Members upsert own bible streak"
  on public.bible_streaks
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and church_id = public.grace_connect_leaderboard_church_id()
  );

drop policy if exists "Members update own bible streak"
  on public.bible_streaks;
create policy "Members update own bible streak"
  on public.bible_streaks
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and church_id = public.grace_connect_leaderboard_church_id()
  );

create or replace function public.upsert_my_bible_streak(
  streak_count integer,
  last_read_date date
)
returns public.bible_streaks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id text;
  v_display_name text;
  v_photo_url text;
  updated_row public.bible_streaks;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select
    nullif(u."placeId", ''),
    coalesce(nullif(trim(u."fullName"), ''), nullif(trim(u.email), ''), 'Member'),
    u."photoUrl"
  into v_church_id, v_display_name, v_photo_url
  from public.users u
  where u.id = auth.uid()
     or u.uid = auth.uid()::text
  limit 1;

  v_church_id := coalesce(
    nullif(public.viewer_effective_church_id(), ''),
    nullif(v_church_id, ''),
    public.grace_connect_global_church_id()
  );
  v_display_name := coalesce(nullif(v_display_name, ''), auth.jwt()->>'email', 'Member');

  insert into public.bible_streaks (
    user_id,
    church_id,
    user_name,
    photo_url,
    streak_count,
    last_read_date,
    updated_at
  )
  values (
    auth.uid(),
    v_church_id,
    v_display_name,
    v_photo_url,
    greatest(coalesce(streak_count, 0), 0),
    last_read_date,
    now()
  )
  on conflict (user_id) do update
    set church_id = excluded.church_id,
        user_name = excluded.user_name,
        photo_url = excluded.photo_url,
        streak_count = excluded.streak_count,
        last_read_date = excluded.last_read_date,
        updated_at = now()
  returning * into updated_row;

  return updated_row;
end;
$$;

create or replace function public.list_bible_streak_leaderboard(
  result_limit integer default 25
)
returns table (
  user_id text,
  user_name text,
  photo_url text,
  streak_count integer,
  last_read_date date
)
language sql
stable
security definer
set search_path = public
as $$
  select
    bs.user_id::text,
    bs.user_name,
    bs.photo_url,
    bs.streak_count,
    bs.last_read_date
  from public.bible_streaks bs
  where bs.church_id = public.grace_connect_leaderboard_church_id()
  order by bs.streak_count desc, bs.last_read_date desc nulls last, bs.updated_at desc
  limit greatest(1, least(coalesce(result_limit, 25), 100));
$$;

create or replace function public.get_my_grace_circle_status(target_circle_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case
        when m.status = 'active' and m.role = 'owner' then 'owner'
        else m.status
      end
      from public.grace_circle_members m
      where m.circle_id = target_circle_id
        and m.user_id = auth.uid()::text
      limit 1
    ),
    case
      when exists (
        select 1
        from public.grace_circles c
        where c.id = target_circle_id
          and c.owner_id = auth.uid()::text
      ) then 'owner'
      else 'none'
    end
  );
$$;

drop function if exists public.join_grace_circle(uuid);
create function public.join_grace_circle(target_circle_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  circle public.grace_circles%rowtype;
  target_status text;
  next_status text;
begin
  if actor_id is null or actor_id = '' then
    raise exception 'Not authenticated';
  end if;

  select *
    into circle
    from public.grace_circles
    where id = target_circle_id;

  if circle.id is null then
    raise exception 'Grace Circle not found';
  end if;

  if circle.owner_id = actor_id then
    target_status := 'active';
  elsif coalesce(circle.join_mode, 'approval') = 'open' then
    target_status := 'active';
  else
    target_status := 'pending';
  end if;

  insert into public.grace_circle_members (circle_id, user_id, role, status)
  values (
    target_circle_id,
    actor_id,
    case when circle.owner_id = actor_id then 'owner' else 'member' end,
    target_status
  )
  on conflict (circle_id, user_id) do update
    set status = case
          when public.grace_circle_members.status = 'active' then 'active'
          else excluded.status
        end,
        role = case
          when circle.owner_id = actor_id then 'owner'
          else public.grace_circle_members.role
        end
  returning status into next_status;

  update public.grace_circles
  set member_count = (
        select count(*)::integer
        from public.grace_circle_members
        where circle_id = target_circle_id
          and status = 'active'
      ),
      updated_at = now()
  where id = target_circle_id;

  return coalesce(next_status, target_status);
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
       select 1
       from public.grace_circle_members m
       where m.circle_id = grace_circles.id
         and m.user_id = auth.uid()::text
     )
  order by created_at desc;
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
  with viewer as (
    select coalesce(nullif(trim(viewer_church_id), ''), public.viewer_effective_church_id()) as church_id
  )
  select p.*
  from public.community_posts p
  cross join viewer v
  where (p.expires_at is null or p.expires_at > now())
    and (
      case
        when feed_mode = 'church' then
          v.church_id is not null and p.place_id = v.church_id
        when feed_mode = 'circle' then
          target_circle_id is not null
          and p.circle_id::text = target_circle_id
          and exists (
            select 1
            from public.grace_circle_members m
            where m.circle_id = p.circle_id
              and m.user_id = auth.uid()::text
              and m.status = 'active'
          )
        when feed_mode = 'following' then
          exists (
            select 1
            from public.social_follows f
            where f.follower_id = auth.uid()::text
              and f.following_id = p.author_id::text
              and f.status = 'accepted'
          )
          or exists (
            select 1
            from public.grace_circle_members m
            where m.user_id = auth.uid()::text
              and m.status = 'active'
              and p.circle_id is not null
              and m.circle_id = p.circle_id
          )
        else
          p.visible_to_all_churches or p.scope in ('global', 'discover', 'public')
      end
    )
  order by p.created_at desc
  limit greatest(1, least(coalesce(result_limit, 75), 200));
$$;

create or replace function public.grace_room_anonymous_name(
  target_room_id uuid,
  target_user_id text
)
returns text
language plpgsql
immutable
as $$
declare
  adjectives text[] := array[
    'Gentle', 'Steady', 'Hopeful', 'Quiet', 'Brave', 'Kind',
    'Patient', 'Bright', 'Tender', 'Faithful', 'Peaceful', 'Lifted'
  ];
  nouns text[] := array[
    'Grace', 'Mercy', 'Light', 'Anchor', 'Branch', 'River',
    'Song', 'Shelter', 'Dawn', 'Path', 'Bloom', 'Flame'
  ];
  seed bigint := abs(hashtext(target_room_id::text || ':' || coalesce(target_user_id, ''))::bigint);
  suffix text := substr(md5(target_room_id::text || ':' || coalesce(target_user_id, '')), 1, 3);
begin
  return adjectives[(seed % array_length(adjectives, 1))::integer + 1]
    || ' '
    || nouns[((seed / 13) % array_length(nouns, 1))::integer + 1]
    || ' '
    || suffix;
end;
$$;

update public.grace_room_participants
set anonymous_name = public.grace_room_anonymous_name(room_id, user_id)
where nullif(trim(coalesce(user_id, '')), '') is not null;

create or replace function public.join_grace_room(target_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
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
    room_id, user_id, anonymous_name, last_seen_at
  )
  values (
    target_room_id,
    actor_id,
    public.grace_room_anonymous_name(target_room_id, actor_id),
    now()
  )
  on conflict (room_id, user_id) do update
    set last_seen_at = now(),
        anonymous_name = public.grace_room_anonymous_name(target_room_id, actor_id);

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

grant execute on function public.viewer_effective_church_id() to authenticated;
grant execute on function public.grace_connect_global_church_id() to authenticated;
grant execute on function public.grace_connect_leaderboard_church_id() to authenticated;
grant execute on function public.get_or_create_direct_conversation(text) to authenticated;
grant execute on function public.toggle_community_post_like(uuid) to authenticated;
grant execute on function public.toggle_community_story_like(uuid) to authenticated;
grant execute on function public.is_live_stream_church_member(text) to authenticated;
grant execute on function public.is_live_stream_visible_to_viewer(text) to authenticated;
grant execute on function public.list_visible_live_churches(text, integer) to authenticated;
grant execute on function public.record_live_stream_viewer_heartbeat(text) to authenticated;
grant execute on function public.get_live_stream_viewer_count(text) to authenticated;
grant execute on function public.upsert_my_bible_streak(integer, date) to authenticated;
grant execute on function public.list_bible_streak_leaderboard(integer) to authenticated;
grant execute on function public.get_my_grace_circle_status(uuid) to authenticated;
grant execute on function public.join_grace_circle(uuid) to authenticated;
grant execute on function public.list_grace_circles() to authenticated;
grant execute on function public.grace_room_anonymous_name(uuid, text) to authenticated;
grant execute on function public.join_grace_room(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
