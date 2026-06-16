-- Product fixes for feed scope/interactions, confidential care assignment,
-- Bible streak leaderboards, scheduled announcements, and cross-church messaging.

create extension if not exists pgcrypto;

-- Cross-church feed interactions.
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;

drop policy if exists "Authenticated users view active community posts"
  on public.community_posts;
create policy "Authenticated users view active community posts"
  on public.community_posts
  for select
  to authenticated
  using (
    expires_at is null or expires_at > now()
  );

drop policy if exists "Members create community comments"
  on public.community_comments;
create policy "Members create community comments"
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
    )
  );

drop policy if exists "Authenticated users view community comments"
  on public.community_comments;
create policy "Authenticated users view community comments"
  on public.community_comments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.community_posts p
      where p.id = post_id
        and (p.expires_at is null or p.expires_at > now())
    )
  );

drop policy if exists "Members delete own community comments"
  on public.community_comments;
create policy "Members delete own community comments"
  on public.community_comments
  for delete
  to authenticated
  using (author_id::text = auth.uid()::text);

create or replace function public.toggle_community_post_like(post_id uuid)
returns public.community_posts
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid text := auth.uid()::text;
  updated_post public.community_posts;
begin
  if auth.uid() is null then
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
    returning * into updated_post;

  if not found then
    raise exception 'Post not found or unavailable';
  end if;

  return updated_post;
end;
$$;

grant execute on function public.toggle_community_post_like(uuid)
  to authenticated;

create or replace function public.toggle_community_story_like(target_story_id uuid)
returns public.community_stories
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
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
    returning * into updated_story;

  if updated_story.id is null then
    raise exception 'Status not found';
  end if;

  return updated_story;
end;
$$;

grant execute on function public.toggle_community_story_like(uuid)
  to authenticated;

-- Messaging can be started with people surfaced by global search/feed, while
-- still respecting blocks and each user's message preference.
drop policy if exists "Members create direct conversations"
  on public.direct_conversations;
create policy "Members create direct conversations"
  on public.direct_conversations
  for insert
  to authenticated
  with check (
    created_by = auth.uid()::text
    and auth.uid()::text = any(member_ids)
    and church_id = public.get_church_id()
    and (
      select count(*)
      from public.users u
      where u.uid = any(member_ids)
        and coalesce(u."allowMessages", true)
    ) = 2
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
  actor_church_id text := public.get_church_id();
  conversation_key text;
  existing_conversation public.direct_conversations;
  new_conversation public.direct_conversations;
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

  if actor_church_id is null or actor_church_id = '' then
    raise exception 'Join a church before starting messages';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.uid = clean_other_user_id
      and coalesce(u."allowMessages", true)
  ) then
    raise exception 'This member is not accepting messages right now';
  end if;

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = actor_uid and b.blocked_user_id = clean_other_user_id)
       or (b.blocker_id = clean_other_user_id and b.blocked_user_id = actor_uid)
  ) then
    raise exception 'Messages are not available with this member';
  end if;

  select string_agg(value, ':' order by value)
    into conversation_key
    from unnest(array[actor_uid, clean_other_user_id]) as value;

  select *
    into existing_conversation
    from public.direct_conversations
    where participant_key = conversation_key
    limit 1;

  if existing_conversation.id is not null then
    update public.direct_conversations
      set hidden_for = array_remove(
        array_remove(coalesce(hidden_for, '{}'::text[]), actor_uid),
        clean_other_user_id
      )
      where id = existing_conversation.id
      returning * into existing_conversation;

    return existing_conversation;
  end if;

  insert into public.direct_conversations (
    church_id,
    member_ids,
    participant_key,
    created_by,
    last_message_at
  )
  values (
    actor_church_id,
    array[actor_uid, clean_other_user_id],
    conversation_key,
    actor_uid,
    now()
  )
  returning * into new_conversation;

  return new_conversation;
end;
$$;

grant execute on function public.get_or_create_direct_conversation(text)
  to authenticated;

-- Confidential prayer/counseling assignment.
alter table public.prayer_requests
  add column if not exists "assignedToHelperId" text;

create index if not exists prayer_requests_assigned_idx
  on public.prayer_requests ("churchId", "assignedToHelperId");

create or replace function public.has_app_privilege(privilege_name text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where (u.id = auth.uid() or u.uid = auth.uid()::text)
      and trim(coalesce(privilege_name, '')) = any(coalesce(u."appPrivileges", '{}'::text[]))
  );
$$;

grant execute on function public.has_app_privilege(text) to authenticated;

create or replace function public.assign_member_role(
  target_uid text,
  role_name text,
  church_id text,
  role_action text default 'add'
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_church_id text := public.get_church_id();
  next_roles text[];
  notification_action text;
  actor_name text;
  target_name text;
  normalized_role text := regexp_replace(
    lower(trim(coalesce(role_name, ''))),
    '[^a-z0-9]+',
    '_',
    'g'
  );
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage roles for your church';
  end if;

  if not (
    public.has_any_role(array['Pastor', 'Senior Pastor']) or
    public.has_app_privilege('manageRoles')
  ) then
    raise exception 'You do not have permission to assign roles';
  end if;

  if normalized_role in ('pastor', 'senior_pastor') and
     not public.has_any_role(array['Pastor', 'Senior Pastor']) then
    raise exception 'Only the Pastor and Senior Pastor can assign pastor roles';
  end if;

  select coalesce(nullif("fullName", ''), nullif(email, ''), actor_uid)
    into actor_name
    from public.users
    where uid = actor_uid
    limit 1;

  select coalesce(nullif("fullName", ''), nullif(email, ''), target_uid)
    into target_name
    from public.users
    where uid = target_uid
      and "placeId" = church_id
    limit 1;

  if target_name is null then
    raise exception 'Target member was not found in your church';
  end if;

  if lower(coalesce(role_action, 'add')) = 'remove' then
    update public.users
    set roles = coalesce(
      nullif(array_remove(coalesce(roles, '{}'::text[]), role_name), '{}'::text[]),
      array['Member']::text[]
    )
    where uid = target_uid
    returning roles into next_roles;
    notification_action := 'removed';
  else
    update public.users
    set roles = (
      select array_agg(distinct role_value)
      from unnest(coalesce(roles, '{}'::text[]) || role_name) as role_value
      where nullif(trim(role_value), '') is not null
    )
    where uid = target_uid
    returning roles into next_roles;
    notification_action := 'assigned';
  end if;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    church_id,
    case when notification_action = 'removed'
      then 'role_removed'
      else 'role_assigned'
    end,
    actor_uid,
    jsonb_build_object(
      'targetUid', target_uid,
      'targetName', target_name,
      'performedByName', coalesce(actor_name, actor_uid),
      'roleChanged', role_name,
      'rolesAfter', next_roles,
      'context',
        coalesce(actor_name, 'A leader') || ' ' || notification_action ||
        ' ' || role_name || ' for ' || target_name
    )
  );

  begin
    perform public.create_notification(
      target_uid::uuid,
      actor_uid::uuid,
      'role_changed',
      'Role updated',
      'Your ' || role_name || ' role was ' || notification_action || '.',
      church_id,
      'users',
      target_uid,
      '/notifications'
    );
  exception when others then
    null;
  end;

  return 'ok';
end;
$$;

grant execute on function public.assign_member_role(text, text, text, text)
  to authenticated;

create or replace function public.assign_member_privileges(
  target_uid text,
  privilege_names text[],
  church_id text
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_church_id text := public.get_church_id();
  cleaned_privileges text[];
  actor_name text;
  target_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage privileges for your church';
  end if;

  if not (
    public.has_any_role(array['Pastor', 'Senior Pastor']) or
    public.has_app_privilege('manageRoles')
  ) then
    raise exception 'You do not have permission to assign privileges';
  end if;

  select coalesce(nullif("fullName", ''), nullif(email, ''), actor_uid)
    into actor_name
    from public.users
    where uid = actor_uid
    limit 1;

  select coalesce(nullif("fullName", ''), nullif(email, ''), target_uid)
    into target_name
    from public.users
    where uid = target_uid
      and "placeId" = church_id
    limit 1;

  if target_name is null then
    raise exception 'Target member was not found in your church';
  end if;

  select coalesce(array_agg(distinct clean_value), '{}'::text[])
    into cleaned_privileges
    from (
      select trim(value) as clean_value
      from unnest(coalesce(privilege_names, '{}'::text[])) as value
      where trim(value) <> ''
    ) cleaned;

  update public.users
  set "appPrivileges" = cleaned_privileges
  where uid = target_uid;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    church_id,
    'privileges_updated',
    actor_uid,
    jsonb_build_object(
      'targetUid', target_uid,
      'targetName', target_name,
      'performedByName', coalesce(actor_name, actor_uid),
      'privilegesAfter', cleaned_privileges,
      'context',
        coalesce(actor_name, 'A leader') || ' updated app privileges for ' ||
        target_name
    )
  );

  begin
    perform public.create_notification(
      target_uid::uuid,
      actor_uid::uuid,
      'role_changed',
      'Access updated',
      'Your Grace Connect app access privileges were updated.',
      church_id,
      'users',
      target_uid,
      '/notifications'
    );
  exception when others then
    null;
  end;

  return 'ok';
end;
$$;

grant execute on function public.assign_member_privileges(text, text[], text)
  to authenticated;

create or replace function public.can_assign_care_requests()
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.has_any_role(array['Pastor', 'Senior Pastor', 'Acting Pastor'])
    or public.has_app_privilege('assignCareRequests');
$$;

grant execute on function public.can_assign_care_requests() to authenticated;

drop policy if exists "Church prayer visibility" on public.prayer_requests;
drop policy if exists "Prayer team updates prayers" on public.prayer_requests;

create policy "Church prayer visibility"
  on public.prayer_requests
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
      or "isPrivate" is not true
    )
  );

create policy "Prayer team updates prayers"
  on public.prayer_requests
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
    )
  );

create or replace function public.assign_prayer_helper(
  request_id text,
  helper_uid text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_uuid uuid := auth.uid();
  actor_church_id text := public.get_church_id();
  target_church_id text;
  helper_user_id uuid;
  helper_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_assign_care_requests() then
    raise exception 'You do not have permission to assign confidential requests';
  end if;

  select "churchId"
    into target_church_id
  from public.prayer_requests
  where id = request_id;

  if target_church_id is null then
    raise exception 'Prayer request not found';
  end if;

  if target_church_id is distinct from actor_church_id then
    raise exception 'You can only assign prayer requests for your church';
  end if;

  if nullif(helper_uid, '') is not null then
    select u.id, coalesce(nullif(u."fullName", ''), u.email)
      into helper_user_id, helper_name
    from public.users u
    where u.uid = helper_uid
      and u."placeId" = target_church_id
    limit 1;

    if helper_user_id is null then
      raise exception 'Selected helper is not a member of your church';
    end if;
  end if;

  update public.prayer_requests
  set "assignedToHelperId" = nullif(helper_uid, '')
  where id = request_id
    and "churchId" = target_church_id;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    target_church_id,
    'prayer_assigned',
    actor_uid,
    jsonb_build_object(
      'requestId', request_id,
      'assignedTo', nullif(helper_uid, ''),
      'assignedToName', helper_name
    )
  );

  if helper_user_id is not null then
    perform public.create_notification(
      helper_user_id,
      actor_uuid,
      'prayer_assignment',
      'Prayer Request Assigned',
      'A confidential prayer request has been assigned to you.',
      target_church_id,
      'prayer_requests',
      request_id,
      '/prayers'
    );
  end if;

  return 'ok';
end;
$$;

grant execute on function public.assign_prayer_helper(text, text)
  to authenticated;

drop policy if exists "Care team view counseling" on public.counseling_requests;
drop policy if exists "Care team update counseling" on public.counseling_requests;

create policy "Care team view counseling"
  on public.counseling_requests
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
    )
  );

create policy "Care team update counseling"
  on public.counseling_requests
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      public.can_assign_care_requests()
      or "assignedToHelperId" = auth.uid()::text
    )
  );

create or replace function public.assign_counseling_helper(
  request_id text,
  helper_uid text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_user_id uuid := auth.uid();
  actor_church_id text := public.get_church_id();
  target_church_id text;
  helper_user_id uuid;
  helper_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_assign_care_requests() then
    raise exception 'You do not have permission to assign counseling cases';
  end if;

  select "churchId"
    into target_church_id
  from public.counseling_requests
  where id = request_id;

  if target_church_id is null then
    raise exception 'Counseling request not found';
  end if;

  if target_church_id is distinct from actor_church_id then
    raise exception 'You can only assign counseling cases for your church';
  end if;

  if nullif(helper_uid, '') is not null then
    select u.id, coalesce(nullif(u."fullName", ''), u.email)
      into helper_user_id, helper_name
    from public.users u
    where u.uid = helper_uid
      and u."placeId" = target_church_id
    limit 1;

    if helper_user_id is null then
      raise exception 'Selected helper is not a member of your church';
    end if;
  end if;

  update public.counseling_requests
  set "assignedToHelperId" = nullif(helper_uid, '')
  where id = request_id
    and "churchId" = target_church_id;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    target_church_id,
    'counseling_assigned',
    actor_uid,
    jsonb_build_object(
      'requestId', request_id,
      'assignedTo', nullif(helper_uid, ''),
      'assignedToName', helper_name
    )
  );

  if helper_user_id is not null then
    perform public.create_notification(
      helper_user_id,
      actor_user_id,
      'counseling_assignment',
      'Counseling Case Assigned',
      'A pastoral care request has been assigned to you.',
      target_church_id,
      'counseling_requests',
      request_id,
      '/counseling'
    );
  end if;

  return 'ok';
end;
$$;

grant execute on function public.assign_counseling_helper(text, text)
  to authenticated;

create or replace function public.notify_staff_on_prayer_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record record;
  actor_uuid uuid;
begin
  if nullif(new."userId", '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    actor_uuid := new."userId"::uuid;
  end if;

  for staff_record in
    select id
    from public.users u
    where u."placeId" = new."churchId"
      and (
        exists (
          select 1
          from unnest(coalesce(u.roles, '{}'::text[])) as role_name
          where public.normalize_role_name(role_name) = any(array[
            'pastor',
            'senior_pastor',
            'acting_pastor'
          ])
        )
        or 'assignCareRequests' = any(coalesce(u."appPrivileges", '{}'::text[]))
      )
  loop
    perform public.create_notification(
      staff_record.id,
      actor_uuid,
      'prayer_request',
      'New Prayer Request',
      coalesce(nullif(new.title, ''), 'A member submitted a prayer request.'),
      new."churchId",
      'prayer_requests',
      new.id,
      '/prayers'
    );
  end loop;

  return new;
end;
$$;

create or replace function public.notify_staff_on_counseling_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  staff_record record;
  actor_uuid uuid;
begin
  if nullif(new."userId", '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    actor_uuid := new."userId"::uuid;
  end if;

  for staff_record in
    select id
    from public.users u
    where u."placeId" = new."churchId"
      and (
        exists (
          select 1
          from unnest(coalesce(u.roles, '{}'::text[])) as role_name
          where public.normalize_role_name(role_name) = any(array[
            'pastor',
            'senior_pastor',
            'acting_pastor'
          ])
        )
        or 'assignCareRequests' = any(coalesce(u."appPrivileges", '{}'::text[]))
      )
  loop
    perform public.create_notification(
      staff_record.id,
      actor_uuid,
      'counseling_request',
      'New Counseling Request',
      coalesce(new.category, 'Pastoral care') || ' request marked ' || coalesce(new.urgency, 'Low'),
      new."churchId",
      'counseling_requests',
      new.id,
      '/counseling'
    );
  end loop;

  return new;
end;
$$;

-- Bible streak leaderboards.
create table if not exists public.bible_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  church_id text not null,
  user_name text not null default 'Member',
  photo_url text,
  streak_count integer not null default 0 check (streak_count >= 0),
  last_read_date date,
  updated_at timestamptz not null default now()
);

create index if not exists bible_streaks_church_rank_idx
  on public.bible_streaks (church_id, streak_count desc, last_read_date desc);

alter table public.bible_streaks enable row level security;

drop policy if exists "Church members view bible streaks" on public.bible_streaks;
create policy "Church members view bible streaks"
  on public.bible_streaks
  for select
  to authenticated
  using (church_id = public.get_church_id());

drop policy if exists "Members upsert own bible streak" on public.bible_streaks;
create policy "Members upsert own bible streak"
  on public.bible_streaks
  for insert
  to authenticated
  with check (user_id = auth.uid() and church_id = public.get_church_id());

drop policy if exists "Members update own bible streak" on public.bible_streaks;
create policy "Members update own bible streak"
  on public.bible_streaks
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and church_id = public.get_church_id());

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
  profile record;
  updated_row public.bible_streaks;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select "placeId", coalesce(nullif("fullName", ''), email, 'Member') as display_name, "photoUrl"
    into profile
  from public.users
  where id = auth.uid()
  limit 1;

  if profile."placeId" is null or profile."placeId" = '' then
    raise exception 'Join a church before recording a leaderboard streak';
  end if;

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
    profile."placeId",
    profile.display_name,
    profile."photoUrl",
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

grant execute on function public.upsert_my_bible_streak(integer, date)
  to authenticated;

-- Announcement scheduling, links, and map locations.
alter table public.announcements
  add column if not exists scheduled_at timestamptz,
  add column if not exists notified_at timestamptz,
  add column if not exists link_url text,
  add column if not exists location_name text,
  add column if not exists location_address text,
  add column if not exists location_latitude double precision,
  add column if not exists location_longitude double precision,
  add column if not exists google_place_id text;

create index if not exists announcements_due_idx
  on public.announcements (church_id, scheduled_at, notified_at)
  where deleted_at is null;

drop policy if exists "Church members view announcements" on public.announcements;
create policy "Church members view announcements"
  on public.announcements
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and deleted_at is null
    and (expires_at is null or expires_at > now())
    and (scheduled_at is null or scheduled_at <= now())
  );

create or replace function public.send_announcement_notifications(
  target_announcement public.announcements
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  member_record record;
  notification_body text;
begin
  if target_announcement.deleted_at is not null then
    return;
  end if;

  if target_announcement.scheduled_at is not null
      and target_announcement.scheduled_at > now() then
    return;
  end if;

  if target_announcement.notified_at is not null then
    return;
  end if;

  notification_body := left(
    regexp_replace(coalesce(target_announcement.body, ''), '\s+', ' ', 'g'),
    220
  );

  for member_record in
    select id
    from public.users
    where "placeId" = target_announcement.church_id
      and id is not null
  loop
    perform public.create_notification(
      member_record.id,
      target_announcement.author_id,
      'announcement',
      coalesce(nullif(target_announcement.title, ''), 'New church announcement'),
      notification_body,
      target_announcement.church_id,
      'announcements',
      target_announcement.id::text,
      '/announcements'
    );
  end loop;

  update public.announcements
    set notified_at = now()
    where id = target_announcement.id;
end;
$$;

create or replace function public.notify_on_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.send_announcement_notifications(new);
  return new;
end;
$$;

create or replace function public.publish_due_announcements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  announcement_record public.announcements;
  published_count integer := 0;
begin
  for announcement_record in
    select *
    from public.announcements
    where deleted_at is null
      and notified_at is null
      and (scheduled_at is null or scheduled_at <= now())
  loop
    perform public.send_announcement_notifications(announcement_record);
    published_count := published_count + 1;
  end loop;

  return published_count;
end;
$$;

grant execute on function public.publish_due_announcements()
  to authenticated;

create or replace function public.run_graceconnect_daily_cleanup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_stories integer := 0;
  vanishing_result jsonb := '{}'::jsonb;
  deleted_events integer := 0;
  published_announcements integer := 0;
begin
  deleted_stories := public.cleanup_expired_community_stories();
  vanishing_result := public.cleanup_vanishing_content();
  deleted_events := public.cleanup_past_events();
  published_announcements := public.publish_due_announcements();

  return jsonb_build_object(
    'deleted_stories', deleted_stories,
    'vanishing_content', vanishing_result,
    'deleted_events', deleted_events,
    'published_announcements', published_announcements
  );
end;
$$;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'graceconnect-announcements-due') then
      perform cron.unschedule('graceconnect-announcements-due');
    end if;

    perform cron.schedule(
      'graceconnect-announcements-due',
      '*/5 * * * *',
      'select public.publish_due_announcements();'
    );
  end if;
exception when undefined_table or insufficient_privilege then
  null;
end;
$$;

alter table public.bible_streaks replica identity full;

do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array[
      'prayer_requests',
      'counseling_requests',
      'bible_streaks',
      'announcements'
    ]
    loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      end if;
    end loop;
  end if;
end;
$$;
