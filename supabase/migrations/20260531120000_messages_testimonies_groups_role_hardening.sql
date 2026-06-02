create extension if not exists pgcrypto;

alter table public.users
  add column if not exists "allowMessages" boolean not null default true,
  add column if not exists "isProfilePrivate" boolean not null default false;

-- Direct member messages.
create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  member_ids text[] not null,
  participant_key text not null unique,
  created_by text not null,
  last_message text,
  last_sender_id text,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint direct_conversations_two_members
    check (array_length(member_ids, 1) = 2)
);

create index if not exists direct_conversations_member_idx
  on public.direct_conversations using gin (member_ids);

create index if not exists direct_conversations_church_latest_idx
  on public.direct_conversations (church_id, last_message_at desc);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.direct_conversations(id) on delete cascade,
  sender_id text not null,
  text text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists direct_messages_conversation_created_idx
  on public.direct_messages (conversation_id, created_at);

alter table public.direct_conversations enable row level security;
alter table public.direct_messages enable row level security;

drop policy if exists "Members view own direct conversations"
  on public.direct_conversations;
create policy "Members view own direct conversations"
  on public.direct_conversations
  for select
  to authenticated
  using (auth.uid()::text = any(member_ids));

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
        and u."placeId" = church_id
        and coalesce(u."allowMessages", true)
    ) = 2
  );

drop policy if exists "Members update own direct conversations"
  on public.direct_conversations;
create policy "Members update own direct conversations"
  on public.direct_conversations
  for update
  to authenticated
  using (auth.uid()::text = any(member_ids))
  with check (auth.uid()::text = any(member_ids));

drop policy if exists "Members view own direct messages"
  on public.direct_messages;
create policy "Members view own direct messages"
  on public.direct_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and auth.uid()::text = any(c.member_ids)
    )
  );

drop policy if exists "Members send own direct messages"
  on public.direct_messages;
create policy "Members send own direct messages"
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()::text
    and nullif(trim(text), '') is not null
    and exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and auth.uid()::text = any(c.member_ids)
    )
  );

drop policy if exists "Members mark own direct messages read"
  on public.direct_messages;
create policy "Members mark own direct messages read"
  on public.direct_messages
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and auth.uid()::text = any(c.member_ids)
    )
  )
  with check (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and auth.uid()::text = any(c.member_ids)
    )
  );

create or replace function public.notify_on_direct_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_uid text;
  target_uuid uuid;
  target_church text;
begin
  select member_id
    into target_uid
    from public.direct_conversations c
    cross join unnest(c.member_ids) as member(member_id)
    where c.id = new.conversation_id
      and member_id <> new.sender_id
    limit 1;

  select church_id
    into target_church
    from public.direct_conversations
    where id = new.conversation_id;

  begin
    target_uuid := target_uid::uuid;
  exception when others then
    target_uuid := null;
  end;

  if target_uuid is not null then
    perform public.create_notification(
      target_uuid,
      new.sender_id::uuid,
      'direct_message',
      'New message',
      coalesce(public.display_name_for_user(new.sender_id::uuid), 'Someone')
        || ' sent you a message.',
      target_church,
      'direct_messages',
      new.id::text,
      '/inbox'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_direct_message on public.direct_messages;
create trigger trg_notify_on_direct_message
  after insert on public.direct_messages
  for each row execute function public.notify_on_direct_message();

-- Testimonies: reactions only, no comments.
create table if not exists public.testimonies (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  author_id text not null,
  author_name text not null default 'Member',
  content text not null,
  is_anonymous boolean not null default false,
  reactions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists testimonies_church_created_idx
  on public.testimonies (church_id, created_at desc);

alter table public.testimonies enable row level security;

drop policy if exists "Church members view testimonies" on public.testimonies;
create policy "Church members view testimonies"
  on public.testimonies
  for select
  to authenticated
  using (church_id = public.get_church_id());

drop policy if exists "Church members add testimonies" on public.testimonies;
create policy "Church members add testimonies"
  on public.testimonies
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and author_id = auth.uid()::text
    and nullif(trim(content), '') is not null
  );

drop policy if exists "Authors and pastors delete testimonies"
  on public.testimonies;
create policy "Authors and pastors delete testimonies"
  on public.testimonies
  for delete
  to authenticated
  using (
    author_id = auth.uid()::text
    or (
      church_id = public.get_church_id()
      and public.has_any_role(array['Pastor', 'Senior Pastor'])
    )
  );

create or replace function public.toggle_testimony_reaction(
  target_testimony_id uuid,
  reaction_emoji text
)
returns public.testimonies
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid text := auth.uid()::text;
  current_reactions jsonb;
  current_users jsonb;
  next_users jsonb;
  updated_testimony public.testimonies;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if nullif(trim(reaction_emoji), '') is null then
    raise exception 'Reaction is required';
  end if;

  select coalesce(reactions, '{}'::jsonb)
    into current_reactions
    from public.testimonies
    where id = target_testimony_id
      and church_id = public.get_church_id()
    for update;

  if not found then
    raise exception 'Testimony not found';
  end if;

  current_users := coalesce(current_reactions -> reaction_emoji, '[]'::jsonb);

  if current_users ? current_uid then
    next_users := current_users - current_uid;
  else
    next_users := current_users || jsonb_build_array(current_uid);
  end if;

  update public.testimonies
    set reactions = jsonb_set(
      current_reactions,
      array[reaction_emoji],
      next_users,
      true
    )
    where id = target_testimony_id
    returning * into updated_testimony;

  return updated_testimony;
end;
$$;

grant execute on function public.toggle_testimony_reaction(uuid, text)
  to authenticated;

-- Instagram-style community stories that expire after 24 hours.
create table if not exists public.community_stories (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  author_id text not null,
  author_name text not null default 'Member',
  author_photo text,
  caption text,
  media_url text,
  media_path text,
  media_type text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

alter table public.community_stories
  add column if not exists media_path text;

create index if not exists community_stories_church_active_idx
  on public.community_stories (church_id, expires_at desc, created_at desc);

alter table public.community_stories enable row level security;

drop policy if exists "Church members view active stories"
  on public.community_stories;
create policy "Church members view active stories"
  on public.community_stories
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and expires_at > now()
  );

drop policy if exists "Church members add stories"
  on public.community_stories;
create policy "Church members add stories"
  on public.community_stories
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and author_id = auth.uid()::text
    and expires_at <= now() + interval '25 hours'
  );

drop policy if exists "Authors delete own stories"
  on public.community_stories;
create policy "Authors delete own stories"
  on public.community_stories
  for delete
  to authenticated
  using (
    author_id = auth.uid()::text
    or expires_at <= now()
    or (
      church_id = public.get_church_id()
      and public.has_any_role(array['Pastor', 'Senior Pastor'])
    )
  );

create or replace function public.delete_community_story_media()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if old.media_path is not null and old.media_path <> '' then
    delete from storage.objects
      where bucket_id = 'community_media'
        and name = old.media_path;
  end if;

  return old;
end;
$$;

drop trigger if exists community_story_media_cleanup
  on public.community_stories;
create trigger community_story_media_cleanup
  after delete on public.community_stories
  for each row
  execute function public.delete_community_story_media();

create or replace function public.cleanup_expired_community_stories()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  delete from public.community_stories
    where expires_at <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.cleanup_expired_community_stories()
  to authenticated;

-- Study group chat and leader settings.
create table if not exists public.study_groups (
  id text primary key,
  name text not null default '',
  topic text not null default '',
  description text not null default '',
  "leaderId" text not null,
  "leaderName" text not null default 'Unknown',
  "adminIds" text[] not null default '{}'::text[],
  "memberIds" text[] not null default '{}'::text[],
  schedule text not null default '',
  "churchId" text not null,
  "createdAt" timestamptz not null default now(),
  "allowMemberMessages" boolean not null default true,
  "isPrivate" boolean not null default false,
  "requireJoinApproval" boolean not null default false
);

alter table public.study_groups
  add column if not exists "adminIds" text[] not null default '{}'::text[],
  add column if not exists "allowMemberMessages" boolean not null default true,
  add column if not exists "isPrivate" boolean not null default false,
  add column if not exists "requireJoinApproval" boolean not null default false;

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  "groupId" text not null references public.study_groups(id) on delete cascade,
  "senderId" text not null,
  "senderName" text not null default 'Member',
  text text not null,
  timestamp timestamptz not null default now()
);

create index if not exists study_groups_church_idx
  on public.study_groups ("churchId");

create index if not exists group_messages_group_timestamp_idx
  on public.group_messages ("groupId", timestamp desc);

alter table public.study_groups enable row level security;
alter table public.group_messages enable row level security;

drop policy if exists "Church members view visible study groups"
  on public.study_groups;
create policy "Church members view visible study groups"
  on public.study_groups
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      not "isPrivate"
      or auth.uid()::text = "leaderId"
      or auth.uid()::text = any("adminIds")
      or auth.uid()::text = any("memberIds")
    )
  );

drop policy if exists "Church members create study groups"
  on public.study_groups;
create policy "Church members create study groups"
  on public.study_groups
  for insert
  to authenticated
  with check (
    "churchId" = public.get_church_id()
    and "leaderId" = auth.uid()::text
    and auth.uid()::text = any("memberIds")
  );

drop policy if exists "Group admins update study groups"
  on public.study_groups;
create policy "Group admins update study groups"
  on public.study_groups
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      auth.uid()::text = "leaderId"
      or auth.uid()::text = any("adminIds")
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      auth.uid()::text = "leaderId"
      or auth.uid()::text = any("adminIds")
    )
  );

drop policy if exists "Group members view messages"
  on public.group_messages;
create policy "Group members view messages"
  on public.group_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.study_groups g
      where g.id = "groupId"
        and g."churchId" = public.get_church_id()
        and (
          auth.uid()::text = g."leaderId"
          or auth.uid()::text = any(g."adminIds")
          or auth.uid()::text = any(g."memberIds")
        )
    )
  );

drop policy if exists "Allowed group members send messages"
  on public.group_messages;
create policy "Allowed group members send messages"
  on public.group_messages
  for insert
  to authenticated
  with check (
    "senderId" = auth.uid()::text
    and nullif(trim(text), '') is not null
    and exists (
      select 1
      from public.study_groups g
      where g.id = "groupId"
        and g."churchId" = public.get_church_id()
        and (
          auth.uid()::text = g."leaderId"
          or auth.uid()::text = any(g."adminIds")
          or (
            g."allowMemberMessages"
            and auth.uid()::text = any(g."memberIds")
          )
        )
    )
  );

create or replace function public.join_study_group(target_group_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if target_group."requireJoinApproval"
     and auth.uid()::text <> target_group."leaderId"
     and auth.uid()::text <> all(coalesce(target_group."adminIds", '{}'::text[])) then
    raise exception 'This group requires leader approval to join';
  end if;

  update public.study_groups
    set "memberIds" = (
      select array(
        select distinct member_id
        from unnest(coalesce("memberIds", '{}'::text[]) || auth.uid()::text)
          as member(member_id)
        where member_id is not null and member_id <> ''
      )
    )
    where id = target_group_id;
end;
$$;

create or replace function public.leave_study_group(target_group_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if auth.uid()::text = target_group."leaderId" then
    raise exception 'The group leader cannot leave their own group';
  end if;

  update public.study_groups
    set "memberIds" = array_remove(
      coalesce("memberIds", '{}'::text[]),
      auth.uid()::text
    ),
        "adminIds" = array_remove(
      coalesce("adminIds", '{}'::text[]),
      auth.uid()::text
    )
    where id = target_group_id;
end;
$$;

grant execute on function public.join_study_group(text) to authenticated;
grant execute on function public.leave_study_group(text) to authenticated;

-- Pastor-only role assignment with notifications.
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
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage roles for your church';
  end if;

  if not public.has_any_role(array['Pastor', 'Senior Pastor']) then
    raise exception 'Only the Pastor and Senior Pastor can assign roles';
  end if;

  if not exists (
    select 1
    from public.users
    where uid = target_uid
      and "placeId" = church_id
  ) then
    raise exception 'Target member was not found in your church';
  end if;

  if lower(coalesce(role_action, 'add')) = 'remove' then
    update public.users
    set roles = array_remove(coalesce(roles, '{}'::text[]), role_name)
    where uid = target_uid
    returning roles into next_roles;
    notification_action := 'removed';
  else
    update public.users
    set roles = (
      select array_agg(distinct role_value)
      from unnest(coalesce(roles, '{}'::text[]) || role_name) as role_value
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
      'roleChanged', role_name,
      'rolesAfter', next_roles
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

alter table public.direct_conversations replica identity full;
alter table public.direct_messages replica identity full;
alter table public.testimonies replica identity full;
alter table public.community_stories replica identity full;
alter table public.study_groups replica identity full;
alter table public.group_messages replica identity full;

do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array[
      'direct_conversations',
      'direct_messages',
      'testimonies',
      'community_stories',
      'study_groups',
      'group_messages'
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
