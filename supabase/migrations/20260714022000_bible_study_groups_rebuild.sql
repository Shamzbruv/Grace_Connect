-- Bible Study Groups rebuild foundation.
-- Adds structured group profiles, membership records, reading-plan tables, and
-- secure RPCs while preserving the legacy array fields used by older builds.

alter table public.study_groups
  add column if not exists "profilePhotoUrl" text,
  add column if not exists "coverPhotoUrl" text,
  add column if not exists "profilePhotoPath" text,
  add column if not exists "coverPhotoPath" text,
  add column if not exists "visibility" text not null default 'church',
  add column if not exists "joinMode" text not null default 'approval',
  add column if not exists "status" text not null default 'active',
  add column if not exists "groupType" text not null default 'bible_study',
  add column if not exists "maxMembers" integer,
  add column if not exists "welcomeMessage" text,
  add column if not exists "guidelines" text,
  add column if not exists "currentBook" text,
  add column if not exists "currentChapter" integer,
  add column if not exists "studyStartDate" date,
  add column if not exists "studyEndDate" date,
  add column if not exists "meetingLocation" text,
  add column if not exists "meetingLink" text,
  add column if not exists "updatedAt" timestamptz not null default now(),
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by text,
  add column if not exists archive_reason text;

update public.study_groups
   set "visibility" = case when coalesce("isPrivate", false) then 'private' else coalesce(nullif("visibility", ''), 'church') end,
       "joinMode" = case when coalesce("requireJoinApproval", false) then 'approval' else coalesce(nullif("joinMode", ''), 'open') end,
       "status" = coalesce(nullif("status", ''), 'active'),
       "groupType" = coalesce(nullif("groupType", ''), 'bible_study'),
       "updatedAt" = coalesce("updatedAt", now());

do $$
begin
  alter table public.study_groups
    drop constraint if exists study_groups_visibility_check,
    drop constraint if exists study_groups_join_mode_check,
    drop constraint if exists study_groups_status_check,
    drop constraint if exists study_groups_group_type_check,
    drop constraint if exists study_groups_max_members_check;

  alter table public.study_groups
    add constraint study_groups_visibility_check
      check ("visibility" in ('church', 'private', 'invitation_only')),
    add constraint study_groups_join_mode_check
      check ("joinMode" in ('open', 'approval', 'invitation_only', 'closed')),
    add constraint study_groups_status_check
      check ("status" in ('draft', 'active', 'paused', 'completed', 'archived')),
    add constraint study_groups_group_type_check
      check ("groupType" in ('bible_study', 'discipleship', 'topical', 'ministry', 'other')),
    add constraint study_groups_max_members_check
      check ("maxMembers" is null or "maxMembers" > 0);
end $$;

create index if not exists study_groups_church_status_idx
  on public.study_groups ("churchId", "status", "visibility", "joinMode");

create table if not exists public.study_group_memberships (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  user_id text not null,
  membership_status text not null default 'active',
  group_role text not null default 'member',
  invited_by text,
  requested_at timestamptz,
  approved_at timestamptz,
  approved_by text,
  declined_at timestamptz,
  removed_at timestamptz,
  removed_by text,
  removal_reason text,
  joined_at timestamptz,
  last_opened_at timestamptz,
  notification_level text not null default 'all',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, user_id),
  constraint study_group_memberships_status_check
    check (membership_status in ('invited', 'pending', 'active', 'declined', 'removed', 'left', 'blocked')),
  constraint study_group_memberships_role_check
    check (group_role in ('leader', 'co_leader', 'admin', 'facilitator', 'member', 'observer')),
  constraint study_group_memberships_notification_check
    check (notification_level in ('all', 'mentions', 'muted'))
);

create index if not exists study_group_memberships_user_idx
  on public.study_group_memberships (user_id, membership_status);
create index if not exists study_group_memberships_group_idx
  on public.study_group_memberships (group_id, membership_status, group_role);

create table if not exists public.study_group_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  invited_user_id text not null,
  invited_by text not null,
  invitation_status text not null default 'invited',
  message text,
  expires_at timestamptz,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (group_id, invited_user_id),
  constraint study_group_invitations_status_check
    check (invitation_status in ('invited', 'accepted', 'declined', 'cancelled', 'expired'))
);

create table if not exists public.study_group_reading_plans (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  title text not null default '',
  description text not null default '',
  translation text not null default 'KJV',
  start_date date,
  end_date date,
  created_by text not null,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint study_group_reading_plans_status_check
    check (status in ('draft', 'active', 'paused', 'completed', 'archived'))
);

create table if not exists public.study_group_reading_assignments (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.study_group_reading_plans(id) on delete cascade,
  sequence_number integer not null default 1,
  assigned_date date,
  book text not null default '',
  chapter_start integer,
  chapter_end integer,
  verse_start integer,
  verse_end integer,
  title text not null default '',
  reflection_prompt text,
  discussion_question text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (plan_id, sequence_number)
);

create table if not exists public.study_group_reading_progress (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.study_group_reading_assignments(id) on delete cascade,
  user_id text not null,
  status text not null default 'not_started',
  started_at timestamptz,
  completed_at timestamptz,
  reflection text,
  privacy text not null default 'group_summary',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assignment_id, user_id),
  constraint study_group_reading_progress_status_check
    check (status in ('not_started', 'started', 'completed', 'skipped')),
  constraint study_group_reading_progress_privacy_check
    check (privacy in ('private', 'leader_only', 'group_summary', 'group'))
);

create table if not exists public.study_group_announcements (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  author_id text not null,
  title text not null default '',
  body text not null default '',
  pinned boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_group_resources (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  author_id text not null,
  title text not null default '',
  description text not null default '',
  category text not null default 'Other',
  resource_url text,
  storage_path text,
  approved boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_group_discussion_threads (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  author_id text not null,
  prompt_type text not null default 'reflection',
  title text not null default '',
  body text not null default '',
  scripture_reference text,
  pinned boolean not null default false,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_group_discussion_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.study_group_discussion_threads(id) on delete cascade,
  author_id text not null,
  parent_reply_id uuid references public.study_group_discussion_replies(id) on delete set null,
  body text not null default '',
  is_helpful boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_group_meetings (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  title text not null default '',
  starts_at timestamptz,
  ends_at timestamptz,
  location text,
  meeting_link text,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.study_group_check_ins (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  assignment_id uuid references public.study_group_reading_assignments(id) on delete set null,
  user_id text not null,
  response text not null,
  prayer_visibility text not null default 'personal',
  created_at timestamptz not null default now(),
  constraint study_group_check_ins_visibility_check
    check (prayer_visibility in ('personal', 'leader', 'prayer_team', 'group'))
);

create table if not exists public.study_group_milestones (
  id uuid primary key default gen_random_uuid(),
  group_id text not null references public.study_groups(id) on delete cascade,
  milestone_key text not null,
  title text not null,
  achieved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (group_id, milestone_key)
);

insert into public.study_group_memberships (
  group_id,
  user_id,
  membership_status,
  group_role,
  approved_at,
  approved_by,
  joined_at
)
select g.id, g."leaderId", 'active', 'leader', coalesce(g."createdAt", now()), g."leaderId", coalesce(g."createdAt", now())
from public.study_groups g
where nullif(trim(coalesce(g."leaderId", '')), '') is not null
on conflict (group_id, user_id) do update
set membership_status = 'active',
    group_role = 'leader',
    approved_at = coalesce(public.study_group_memberships.approved_at, excluded.approved_at),
    joined_at = coalesce(public.study_group_memberships.joined_at, excluded.joined_at),
    updated_at = now();

insert into public.study_group_memberships (
  group_id,
  user_id,
  membership_status,
  group_role,
  approved_at,
  approved_by,
  joined_at
)
select g.id, admin_id, 'active', 'admin', coalesce(g."createdAt", now()), g."leaderId", coalesce(g."createdAt", now())
from public.study_groups g
cross join lateral unnest(coalesce(g."adminIds", '{}'::text[])) as admin_id
where nullif(trim(coalesce(admin_id, '')), '') is not null
on conflict (group_id, user_id) do update
set membership_status = 'active',
    group_role = case when public.study_group_memberships.group_role = 'leader' then 'leader' else 'admin' end,
    approved_at = coalesce(public.study_group_memberships.approved_at, excluded.approved_at),
    joined_at = coalesce(public.study_group_memberships.joined_at, excluded.joined_at),
    updated_at = now();

insert into public.study_group_memberships (
  group_id,
  user_id,
  membership_status,
  group_role,
  approved_at,
  approved_by,
  joined_at
)
select g.id, member_id, 'active', 'member', coalesce(g."createdAt", now()), g."leaderId", coalesce(g."createdAt", now())
from public.study_groups g
cross join lateral unnest(coalesce(g."memberIds", '{}'::text[])) as member_id
where nullif(trim(coalesce(member_id, '')), '') is not null
on conflict (group_id, user_id) do update
set membership_status = case
      when public.study_group_memberships.membership_status in ('removed', 'blocked') then public.study_group_memberships.membership_status
      else 'active'
    end,
    group_role = case
      when public.study_group_memberships.group_role in ('leader', 'admin', 'co_leader') then public.study_group_memberships.group_role
      else 'member'
    end,
    approved_at = coalesce(public.study_group_memberships.approved_at, excluded.approved_at),
    joined_at = coalesce(public.study_group_memberships.joined_at, excluded.joined_at),
    updated_at = now();

insert into public.study_group_memberships (
  group_id,
  user_id,
  membership_status,
  group_role,
  requested_at
)
select g.id, pending_id, 'pending', 'member', now()
from public.study_groups g
cross join lateral unnest(coalesce(g."pendingMemberIds", '{}'::text[])) as pending_id
where nullif(trim(coalesce(pending_id, '')), '') is not null
on conflict (group_id, user_id) do update
set membership_status = case
      when public.study_group_memberships.membership_status = 'active' then 'active'
      else 'pending'
    end,
    requested_at = coalesce(public.study_group_memberships.requested_at, excluded.requested_at),
    updated_at = now();

create or replace function public.study_group_sync_arrays(target_group_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.study_groups g
     set "memberIds" = coalesce((
           select array_agg(distinct m.user_id)
           from public.study_group_memberships m
           where m.group_id = g.id
             and m.membership_status = 'active'
             and m.group_role <> 'leader'
         ), '{}'::text[]),
         "adminIds" = coalesce((
           select array_agg(distinct m.user_id)
           from public.study_group_memberships m
           where m.group_id = g.id
             and m.membership_status = 'active'
             and m.group_role in ('admin', 'co_leader')
         ), '{}'::text[]),
         "pendingMemberIds" = coalesce((
           select array_agg(distinct m.user_id)
           from public.study_group_memberships m
           where m.group_id = g.id
             and m.membership_status in ('pending', 'invited')
         ), '{}'::text[]),
         "updatedAt" = now()
   where g.id = target_group_id;
end;
$$;

create or replace function public.study_group_actor_can_create()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  actor_roles text[];
  actor_privileges text[];
begin
  if auth.uid() is null or public.get_church_id() is null then
    return false;
  end if;

  select coalesce(u.roles, '{}'::text[]), coalesce(u."appPrivileges", '{}'::text[])
    into actor_roles, actor_privileges
    from public.users u
   where u.uid = actor_id or u.id = auth.uid()
   limit 1;

  if exists (
    select 1
    from unnest(coalesce(actor_roles, '{}'::text[])) as role_name
    where public.normalize_role_name(role_name) in (
      'pastor',
      'senior_pastor',
      'assistant_pastor',
      'acting_pastor',
      'church_administrator',
      'church_admin',
      'administrator',
      'admin'
    )
  ) then
    return true;
  end if;

  return coalesce(actor_privileges, '{}'::text[]) && array[
    'createStudyGroups',
    'manageStudyGroups'
  ]::text[];
end;
$$;

create or replace function public.study_group_actor_can_manage(
  target_group_id text,
  action_name text default 'manage'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  actor_church text := public.get_church_id();
  target_group public.study_groups;
  actor_roles text[];
  actor_privileges text[];
begin
  if auth.uid() is null or actor_church is null then
    return false;
  end if;

  select *
    into target_group
    from public.study_groups
   where id = target_group_id
     and "churchId" = actor_church;

  if not found then
    return false;
  end if;

  if actor_id = target_group."leaderId"
     or actor_id = any(coalesce(target_group."adminIds", '{}'::text[])) then
    return true;
  end if;

  if exists (
    select 1
    from public.study_group_memberships m
    where m.group_id = target_group_id
      and m.user_id = actor_id
      and m.membership_status = 'active'
      and m.group_role in ('leader', 'co_leader', 'admin', 'facilitator')
  ) then
    return true;
  end if;

  select coalesce(u.roles, '{}'::text[]), coalesce(u."appPrivileges", '{}'::text[])
    into actor_roles, actor_privileges
    from public.users u
   where u.uid = actor_id or u.id = auth.uid()
   limit 1;

  if exists (
    select 1
    from unnest(coalesce(actor_roles, '{}'::text[])) as role_name
    where public.normalize_role_name(role_name) in (
      'pastor',
      'senior_pastor',
      'assistant_pastor',
      'acting_pastor',
      'church_administrator',
      'church_admin',
      'administrator',
      'admin'
    )
  ) then
    return true;
  end if;

  if action_name = 'delete' then
    return 'deleteStudyGroups' = any(coalesce(actor_privileges, '{}'::text[]));
  end if;

  if action_name = 'approve' then
    return coalesce(actor_privileges, '{}'::text[]) && array[
      'approveStudyGroupMembers',
      'manageStudyGroups',
      'moderateStudyGroups'
    ]::text[];
  end if;

  return coalesce(actor_privileges, '{}'::text[]) && array[
    'manageStudyGroups',
    'moderateStudyGroups'
  ]::text[];
end;
$$;

create or replace function public.get_visible_study_groups()
returns setof public.study_groups
language sql
security definer
set search_path = public
as $$
  select g.*
    from public.study_groups g
   where g."churchId" = public.get_church_id()
     and coalesce(g."status", 'active') <> 'archived'
     and (
       (
         coalesce(g."visibility", case when g."isPrivate" then 'private' else 'church' end) = 'church'
         and coalesce(g."joinMode", case when g."requireJoinApproval" then 'approval' else 'open' end) <> 'closed'
       )
       or auth.uid()::text = g."leaderId"
       or auth.uid()::text = any(coalesce(g."adminIds", '{}'::text[]))
       or auth.uid()::text = any(coalesce(g."memberIds", '{}'::text[]))
       or auth.uid()::text = any(coalesce(g."pendingMemberIds", '{}'::text[]))
       or exists (
         select 1
         from public.study_group_memberships m
         where m.group_id = g.id
           and m.user_id = auth.uid()::text
           and m.membership_status in ('active', 'pending', 'invited')
       )
       or public.study_group_actor_can_manage(g.id, 'manage')
     )
   order by g."updatedAt" desc nulls last, g."createdAt" desc nulls last;
$$;

drop function if exists public.create_study_group(jsonb);
create function public.create_study_group(group_payload jsonb)
returns public.study_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  actor_church text := public.get_church_id();
  actor_name text := 'Member';
  created_group public.study_groups;
  clean_id text := coalesce(nullif(trim(group_payload->>'id'), ''), gen_random_uuid()::text);
  clean_join_mode text := coalesce(nullif(group_payload->>'joinMode', ''), 'approval');
  clean_visibility text := coalesce(nullif(group_payload->>'visibility', ''), 'church');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if actor_church is null or trim(actor_church) = '' then
    raise exception 'You must be linked to an active church before creating Bible Study Groups.';
  end if;

  if not public.study_group_actor_can_create() then
    raise exception 'You do not have permission to create Bible Study Groups.';
  end if;

  if nullif(trim(coalesce(group_payload->>'name', '')), '') is null then
    raise exception 'Group name is required.';
  end if;

  if clean_visibility not in ('church', 'private', 'invitation_only') then
    clean_visibility := 'church';
  end if;

  if clean_join_mode not in ('open', 'approval', 'invitation_only', 'closed') then
    clean_join_mode := 'approval';
  end if;

  select coalesce(nullif(u."fullName", ''), nullif(u.email, ''), 'Member')
    into actor_name
    from public.users u
   where u.uid = actor_id or u.id = auth.uid()
   limit 1;

  insert into public.study_groups (
    id,
    name,
    topic,
    description,
    "leaderId",
    "leaderName",
    "adminIds",
    "memberIds",
    "pendingMemberIds",
    schedule,
    "churchId",
    "createdAt",
    "allowMemberMessages",
    "isPrivate",
    "requireJoinApproval",
    "profilePhotoUrl",
    "coverPhotoUrl",
    "profilePhotoPath",
    "coverPhotoPath",
    "visibility",
    "joinMode",
    "status",
    "groupType",
    "maxMembers",
    "welcomeMessage",
    "guidelines",
    "currentBook",
    "currentChapter",
    "studyStartDate",
    "studyEndDate",
    "meetingLocation",
    "meetingLink",
    "updatedAt"
  ) values (
    clean_id,
    trim(group_payload->>'name'),
    coalesce(group_payload->>'topic', ''),
    coalesce(group_payload->>'description', ''),
    actor_id,
    actor_name,
    array[actor_id],
    array[actor_id],
    '{}'::text[],
    coalesce(group_payload->>'schedule', ''),
    actor_church,
    now(),
    coalesce(nullif(group_payload->>'allowMemberMessages', '')::boolean, true),
    clean_visibility <> 'church',
    clean_join_mode in ('approval', 'invitation_only'),
    group_payload->>'profilePhotoUrl',
    group_payload->>'coverPhotoUrl',
    group_payload->>'profilePhotoPath',
    group_payload->>'coverPhotoPath',
    clean_visibility,
    clean_join_mode,
    coalesce(nullif(group_payload->>'status', ''), 'active'),
    coalesce(nullif(group_payload->>'groupType', ''), 'bible_study'),
    nullif(group_payload->>'maxMembers', '')::integer,
    group_payload->>'welcomeMessage',
    group_payload->>'guidelines',
    group_payload->>'currentBook',
    nullif(group_payload->>'currentChapter', '')::integer,
    nullif(group_payload->>'studyStartDate', '')::date,
    nullif(group_payload->>'studyEndDate', '')::date,
    group_payload->>'meetingLocation',
    group_payload->>'meetingLink',
    now()
  )
  returning * into created_group;

  insert into public.study_group_memberships (
    group_id,
    user_id,
    membership_status,
    group_role,
    approved_at,
    approved_by,
    joined_at
  ) values (
    created_group.id,
    actor_id,
    'active',
    'leader',
    now(),
    actor_id,
    now()
  )
  on conflict (group_id, user_id) do update
  set membership_status = 'active',
      group_role = 'leader',
      updated_at = now();

  perform public.study_group_sync_arrays(created_group.id);

  begin
    insert into public.audit_logs ("churchId", action, "performedBy", details)
    values (
      actor_church,
      'study_group_created',
      actor_id,
      jsonb_build_object('groupId', created_group.id, 'name', created_group.name)
    );
  exception when others then
    null;
  end;

  return created_group;
end;
$$;

drop function if exists public.update_study_group(text, jsonb);
create function public.update_study_group(target_group_id text, group_payload jsonb)
returns public.study_groups
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_group public.study_groups;
  clean_join_mode text := coalesce(nullif(group_payload->>'joinMode', ''), 'approval');
  clean_visibility text := coalesce(nullif(group_payload->>'visibility', ''), 'church');
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to update this Bible Study Group.';
  end if;

  if clean_visibility not in ('church', 'private', 'invitation_only') then
    clean_visibility := 'church';
  end if;

  if clean_join_mode not in ('open', 'approval', 'invitation_only', 'closed') then
    clean_join_mode := 'approval';
  end if;

  update public.study_groups
     set name = coalesce(nullif(trim(group_payload->>'name'), ''), name),
         topic = coalesce(group_payload->>'topic', topic),
         description = coalesce(group_payload->>'description', description),
         schedule = coalesce(group_payload->>'schedule', schedule),
         "allowMemberMessages" = coalesce(nullif(group_payload->>'allowMemberMessages', '')::boolean, "allowMemberMessages"),
         "visibility" = clean_visibility,
         "joinMode" = clean_join_mode,
         "isPrivate" = clean_visibility <> 'church',
         "requireJoinApproval" = clean_join_mode in ('approval', 'invitation_only'),
         "profilePhotoUrl" = coalesce(group_payload->>'profilePhotoUrl', "profilePhotoUrl"),
         "coverPhotoUrl" = coalesce(group_payload->>'coverPhotoUrl', "coverPhotoUrl"),
         "profilePhotoPath" = coalesce(group_payload->>'profilePhotoPath', "profilePhotoPath"),
         "coverPhotoPath" = coalesce(group_payload->>'coverPhotoPath', "coverPhotoPath"),
         "status" = coalesce(nullif(group_payload->>'status', ''), "status"),
         "groupType" = coalesce(nullif(group_payload->>'groupType', ''), "groupType"),
         "maxMembers" = coalesce(nullif(group_payload->>'maxMembers', '')::integer, "maxMembers"),
         "welcomeMessage" = coalesce(group_payload->>'welcomeMessage', "welcomeMessage"),
         "guidelines" = coalesce(group_payload->>'guidelines', "guidelines"),
         "currentBook" = coalesce(group_payload->>'currentBook', "currentBook"),
         "currentChapter" = coalesce(nullif(group_payload->>'currentChapter', '')::integer, "currentChapter"),
         "studyStartDate" = coalesce(nullif(group_payload->>'studyStartDate', '')::date, "studyStartDate"),
         "studyEndDate" = coalesce(nullif(group_payload->>'studyEndDate', '')::date, "studyEndDate"),
         "meetingLocation" = coalesce(group_payload->>'meetingLocation', "meetingLocation"),
         "meetingLink" = coalesce(group_payload->>'meetingLink', "meetingLink"),
         "updatedAt" = now()
   where id = target_group_id
     and "churchId" = public.get_church_id()
  returning * into updated_group;

  if not found then
    raise exception 'Group not found.';
  end if;

  return updated_group;
end;
$$;

drop function if exists public.delete_study_group(text, text);
create function public.delete_study_group(
  target_group_id text,
  confirmation_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
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
    raise exception 'Group not found.';
  end if;

  if lower(trim(coalesce(confirmation_name, ''))) <> lower(trim(target_group.name)) then
    raise exception 'Type the exact group name to archive this group.';
  end if;

  if not public.study_group_actor_can_manage(target_group_id, 'delete') then
    raise exception 'You do not have permission to archive this Bible Study Group.';
  end if;

  update public.study_groups
     set "status" = 'archived',
         archived_at = now(),
         archived_by = actor_id,
         archive_reason = 'Archived from Grace Connect',
         "updatedAt" = now()
   where id = target_group_id;

  begin
    insert into public.audit_logs ("churchId", action, "performedBy", details)
    values (
      target_group."churchId",
      'study_group_archived',
      actor_id,
      jsonb_build_object('groupId', target_group.id, 'name', target_group.name)
    );
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'status', 'archived');
end;
$$;

drop function if exists public.archive_study_group(text, text);
create function public.archive_study_group(
  target_group_id text,
  confirmation_name text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.delete_study_group(target_group_id, confirmation_name);
$$;

drop function if exists public.request_to_join_study_group(text);
create function public.request_to_join_study_group(target_group_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
  next_status text := 'active';
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_group
    from public.study_groups
   where id = target_group_id
     and "churchId" = public.get_church_id()
     and coalesce("status", 'active') in ('active', 'paused')
   for update;

  if not found then
    raise exception 'Group not found.';
  end if;

  if coalesce(target_group."joinMode", 'approval') in ('closed', 'invitation_only') then
    if not exists (
      select 1
      from public.study_group_memberships m
      where m.group_id = target_group_id
        and m.user_id = actor_id
        and m.membership_status = 'invited'
    ) then
      raise exception 'This group is invitation only right now.';
    end if;
  end if;

  if exists (
    select 1
    from public.study_group_memberships m
    where m.group_id = target_group_id
      and m.user_id = actor_id
      and m.membership_status = 'active'
  ) then
    return 'active';
  end if;

  if coalesce(target_group."joinMode", 'approval') = 'approval'
     and actor_id <> target_group."leaderId"
     and actor_id <> any(coalesce(target_group."adminIds", '{}'::text[])) then
    next_status := 'pending';
  end if;

  insert into public.study_group_memberships (
    group_id,
    user_id,
    membership_status,
    group_role,
    requested_at,
    approved_at,
    approved_by,
    joined_at
  ) values (
    target_group_id,
    actor_id,
    next_status,
    'member',
    case when next_status = 'pending' then now() else null end,
    case when next_status = 'active' then now() else null end,
    case when next_status = 'active' then actor_id else null end,
    case when next_status = 'active' then now() else null end
  )
  on conflict (group_id, user_id) do update
  set membership_status = excluded.membership_status,
      requested_at = coalesce(public.study_group_memberships.requested_at, excluded.requested_at),
      approved_at = coalesce(public.study_group_memberships.approved_at, excluded.approved_at),
      approved_by = coalesce(public.study_group_memberships.approved_by, excluded.approved_by),
      joined_at = coalesce(public.study_group_memberships.joined_at, excluded.joined_at),
      updated_at = now()
  where public.study_group_memberships.membership_status <> 'blocked';

  perform public.study_group_sync_arrays(target_group_id);
  return next_status;
end;
$$;

drop function if exists public.join_study_group(text);
create function public.join_study_group(target_group_id text)
returns text
language sql
security definer
set search_path = public
as $$
  select public.request_to_join_study_group(target_group_id);
$$;

create or replace function public.approve_study_group_member(
  target_group_id text,
  target_user_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  clean_user_id text := nullif(trim(coalesce(target_user_id, '')), '');
begin
  if clean_user_id is null then
    raise exception 'Member is required.';
  end if;

  if not public.study_group_actor_can_manage(target_group_id, 'approve') then
    raise exception 'You do not have permission to approve members for this group.';
  end if;

  insert into public.study_group_memberships (
    group_id,
    user_id,
    membership_status,
    group_role,
    approved_at,
    approved_by,
    joined_at
  ) values (
    target_group_id,
    clean_user_id,
    'active',
    'member',
    now(),
    actor_id,
    now()
  )
  on conflict (group_id, user_id) do update
  set membership_status = 'active',
      approved_at = now(),
      approved_by = actor_id,
      joined_at = coalesce(public.study_group_memberships.joined_at, now()),
      updated_at = now();

  perform public.study_group_sync_arrays(target_group_id);
  return jsonb_build_object('ok', true, 'status', 'active');
end;
$$;

drop function if exists public.decline_study_group_member(text, text);
create function public.decline_study_group_member(
  target_group_id text,
  target_user_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.study_group_actor_can_manage(target_group_id, 'approve') then
    raise exception 'You do not have permission to decline members for this group.';
  end if;

  update public.study_group_memberships
     set membership_status = 'declined',
         declined_at = now(),
         updated_at = now()
   where group_id = target_group_id
     and user_id = target_user_id;

  perform public.study_group_sync_arrays(target_group_id);
  return jsonb_build_object('ok', true, 'status', 'declined');
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
  actor_id text := auth.uid()::text;
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
    raise exception 'Group not found.';
  end if;

  if actor_id = target_group."leaderId" then
    raise exception 'The group leader cannot leave their own group.';
  end if;

  update public.study_group_memberships
     set membership_status = 'left',
         group_role = 'member',
         updated_at = now()
   where group_id = target_group_id
     and user_id = actor_id;

  perform public.study_group_sync_arrays(target_group_id);
end;
$$;

drop function if exists public.remove_study_group_member(text, text, text);
create function public.remove_study_group_member(
  target_group_id text,
  target_user_id text,
  removal_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to remove members from this group.';
  end if;

  update public.study_group_memberships
     set membership_status = 'removed',
         group_role = 'member',
         removed_at = now(),
         removed_by = auth.uid()::text,
         removal_reason = remove_study_group_member.removal_reason,
         updated_at = now()
   where group_id = target_group_id
     and user_id = target_user_id
     and group_role <> 'leader';

  perform public.study_group_sync_arrays(target_group_id);
  return jsonb_build_object('ok', true, 'status', 'removed');
end;
$$;

drop function if exists public.set_study_group_role(text, text, text);
create function public.set_study_group_role(
  target_group_id text,
  target_user_id text,
  target_role text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_role text := coalesce(nullif(trim(target_role), ''), 'member');
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to manage study group roles.';
  end if;

  if clean_role not in ('co_leader', 'admin', 'facilitator', 'member', 'observer') then
    raise exception 'Unsupported group role.';
  end if;

  update public.study_group_memberships
     set group_role = clean_role,
         membership_status = 'active',
         updated_at = now()
   where group_id = target_group_id
     and user_id = target_user_id
     and group_role <> 'leader';

  perform public.study_group_sync_arrays(target_group_id);
  return jsonb_build_object('ok', true, 'role', clean_role);
end;
$$;

create or replace function public.set_study_group_admin(
  target_group_id text,
  target_user_id text,
  make_admin boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.set_study_group_role(
    target_group_id,
    target_user_id,
    case when make_admin then 'admin' else 'member' end
  );
end;
$$;

drop function if exists public.invite_study_group_member(text, text, text);
create function public.invite_study_group_member(
  target_group_id text,
  target_user_id text,
  invitation_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to invite members to this group.';
  end if;

  insert into public.study_group_invitations (
    group_id,
    invited_user_id,
    invited_by,
    invitation_status,
    message
  ) values (
    target_group_id,
    target_user_id,
    auth.uid()::text,
    'invited',
    invitation_message
  )
  on conflict (group_id, invited_user_id) do update
  set invitation_status = 'invited',
      invited_by = auth.uid()::text,
      message = excluded.message,
      updated_at = now();

  insert into public.study_group_memberships (
    group_id,
    user_id,
    membership_status,
    group_role,
    invited_by
  ) values (
    target_group_id,
    target_user_id,
    'invited',
    'member',
    auth.uid()::text
  )
  on conflict (group_id, user_id) do update
  set membership_status = 'invited',
      invited_by = auth.uid()::text,
      updated_at = now()
  where public.study_group_memberships.membership_status <> 'active';

  perform public.study_group_sync_arrays(target_group_id);
  return jsonb_build_object('ok', true, 'status', 'invited');
end;
$$;

drop function if exists public.create_study_group_reading_plan(jsonb);
create function public.create_study_group_reading_plan(plan_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id text := plan_payload->>'groupId';
  plan_id uuid;
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to create a reading plan for this group.';
  end if;

  insert into public.study_group_reading_plans (
    group_id,
    title,
    description,
    translation,
    start_date,
    end_date,
    created_by,
    status
  ) values (
    target_group_id,
    coalesce(nullif(plan_payload->>'title', ''), 'Bible Study Plan'),
    coalesce(plan_payload->>'description', ''),
    coalesce(nullif(plan_payload->>'translation', ''), 'KJV'),
    nullif(plan_payload->>'startDate', '')::date,
    nullif(plan_payload->>'endDate', '')::date,
    auth.uid()::text,
    coalesce(nullif(plan_payload->>'status', ''), 'active')
  )
  returning id into plan_id;

  return plan_id;
end;
$$;

drop function if exists public.mark_study_assignment_complete(uuid, text);
create function public.mark_study_assignment_complete(
  target_assignment_id uuid,
  reflection_text text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
  target_group_id text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select p.group_id
    into target_group_id
    from public.study_group_reading_assignments a
    join public.study_group_reading_plans p on p.id = a.plan_id
   where a.id = target_assignment_id;

  if target_group_id is null then
    raise exception 'Reading assignment not found.';
  end if;

  if not exists (
    select 1
    from public.study_group_memberships m
    where m.group_id = target_group_id
      and m.user_id = actor_id
      and m.membership_status = 'active'
  ) and not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You must be a member of this group to mark readings complete.';
  end if;

  insert into public.study_group_reading_progress (
    assignment_id,
    user_id,
    status,
    started_at,
    completed_at,
    reflection
  ) values (
    target_assignment_id,
    actor_id,
    'completed',
    now(),
    now(),
    reflection_text
  )
  on conflict (assignment_id, user_id) do update
  set status = 'completed',
      completed_at = now(),
      reflection = coalesce(excluded.reflection, public.study_group_reading_progress.reflection),
      updated_at = now();

  return jsonb_build_object('ok', true, 'status', 'completed');
end;
$$;

drop function if exists public.create_study_group_announcement(jsonb);
create function public.create_study_group_announcement(announcement_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id text := announcement_payload->>'groupId';
  announcement_id uuid;
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to announce in this group.';
  end if;

  insert into public.study_group_announcements (
    group_id,
    author_id,
    title,
    body,
    pinned,
    expires_at
  ) values (
    target_group_id,
    auth.uid()::text,
    coalesce(announcement_payload->>'title', ''),
    coalesce(announcement_payload->>'body', ''),
    coalesce(nullif(announcement_payload->>'pinned', '')::boolean, false),
    nullif(announcement_payload->>'expiresAt', '')::timestamptz
  )
  returning id into announcement_id;

  return announcement_id;
end;
$$;

drop function if exists public.moderate_study_group_message(text, text, text);
create function public.moderate_study_group_message(
  target_group_id text,
  target_message_id text,
  moderation_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.study_group_actor_can_manage(target_group_id, 'manage') then
    raise exception 'You do not have permission to moderate this group.';
  end if;

  if moderation_action = 'delete' then
    delete from public.group_messages
     where id::text = target_message_id
       and "groupId" = target_group_id;
  end if;

  begin
    insert into public.audit_logs ("churchId", action, "performedBy", details)
    select g."churchId",
           'study_group_message_moderated',
           auth.uid()::text,
           jsonb_build_object(
             'groupId', target_group_id,
             'messageId', target_message_id,
             'moderationAction', moderation_action
           )
      from public.study_groups g
     where g.id = target_group_id;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true);
end;
$$;

alter table public.study_group_memberships enable row level security;
alter table public.study_group_invitations enable row level security;
alter table public.study_group_reading_plans enable row level security;
alter table public.study_group_reading_assignments enable row level security;
alter table public.study_group_reading_progress enable row level security;
alter table public.study_group_announcements enable row level security;
alter table public.study_group_resources enable row level security;
alter table public.study_group_discussion_threads enable row level security;
alter table public.study_group_discussion_replies enable row level security;
alter table public.study_group_meetings enable row level security;
alter table public.study_group_check_ins enable row level security;
alter table public.study_group_milestones enable row level security;

drop policy if exists "Study group memberships visible to members and leaders" on public.study_group_memberships;
create policy "Study group memberships visible to members and leaders"
  on public.study_group_memberships for select to authenticated
  using (
    user_id = auth.uid()::text
    or public.study_group_actor_can_manage(group_id, 'manage')
  );

drop policy if exists "Study group invitations visible to invitees and leaders" on public.study_group_invitations;
create policy "Study group invitations visible to invitees and leaders"
  on public.study_group_invitations for select to authenticated
  using (
    invited_user_id = auth.uid()::text
    or public.study_group_actor_can_manage(group_id, 'manage')
  );

drop policy if exists "Study plans visible to group participants" on public.study_group_reading_plans;
create policy "Study plans visible to group participants"
  on public.study_group_reading_plans for select to authenticated
  using (
    public.study_group_actor_can_manage(group_id, 'manage')
    or exists (
      select 1
      from public.study_group_memberships m
      where m.group_id = study_group_reading_plans.group_id
        and m.user_id = auth.uid()::text
        and m.membership_status = 'active'
    )
  );

drop policy if exists "Study assignments visible through plan access" on public.study_group_reading_assignments;
create policy "Study assignments visible through plan access"
  on public.study_group_reading_assignments for select to authenticated
  using (
    exists (
      select 1
      from public.study_group_reading_plans p
      where p.id = study_group_reading_assignments.plan_id
        and (
          public.study_group_actor_can_manage(p.group_id, 'manage')
          or exists (
            select 1
            from public.study_group_memberships m
            where m.group_id = p.group_id
              and m.user_id = auth.uid()::text
              and m.membership_status = 'active'
          )
        )
    )
  );

drop policy if exists "Study progress visible safely" on public.study_group_reading_progress;
create policy "Study progress visible safely"
  on public.study_group_reading_progress for select to authenticated
  using (
    user_id = auth.uid()::text
    or exists (
      select 1
      from public.study_group_reading_assignments a
      join public.study_group_reading_plans p on p.id = a.plan_id
      where a.id = study_group_reading_progress.assignment_id
        and public.study_group_actor_can_manage(p.group_id, 'manage')
    )
  );

drop policy if exists "Study group content visible to participants" on public.study_group_announcements;
create policy "Study group content visible to participants"
  on public.study_group_announcements for select to authenticated
  using (
    public.study_group_actor_can_manage(group_id, 'manage')
    or exists (
      select 1
      from public.study_group_memberships m
      where m.group_id = study_group_announcements.group_id
        and m.user_id = auth.uid()::text
        and m.membership_status = 'active'
    )
  );

drop policy if exists "Study group resources visible to participants" on public.study_group_resources;
create policy "Study group resources visible to participants"
  on public.study_group_resources for select to authenticated
  using (
    public.study_group_actor_can_manage(group_id, 'manage')
    or exists (
      select 1
      from public.study_group_memberships m
      where m.group_id = study_group_resources.group_id
        and m.user_id = auth.uid()::text
        and m.membership_status = 'active'
    )
  );

grant select, insert, update on public.study_group_memberships to authenticated;
grant select, insert, update on public.study_group_invitations to authenticated;
grant select, insert, update on public.study_group_reading_plans to authenticated;
grant select, insert, update on public.study_group_reading_assignments to authenticated;
grant select, insert, update on public.study_group_reading_progress to authenticated;
grant select, insert, update on public.study_group_announcements to authenticated;
grant select, insert, update on public.study_group_resources to authenticated;
grant select, insert, update on public.study_group_discussion_threads to authenticated;
grant select, insert, update on public.study_group_discussion_replies to authenticated;
grant select, insert, update on public.study_group_meetings to authenticated;
grant select, insert, update on public.study_group_check_ins to authenticated;
grant select, insert, update on public.study_group_milestones to authenticated;

grant execute on function public.study_group_sync_arrays(text) to authenticated;
grant execute on function public.study_group_actor_can_create() to authenticated;
grant execute on function public.study_group_actor_can_manage(text, text) to authenticated;
grant execute on function public.get_visible_study_groups() to authenticated;
grant execute on function public.create_study_group(jsonb) to authenticated;
grant execute on function public.update_study_group(text, jsonb) to authenticated;
grant execute on function public.delete_study_group(text, text) to authenticated;
grant execute on function public.archive_study_group(text, text) to authenticated;
grant execute on function public.request_to_join_study_group(text) to authenticated;
grant execute on function public.join_study_group(text) to authenticated;
grant execute on function public.approve_study_group_member(text, text) to authenticated;
grant execute on function public.decline_study_group_member(text, text) to authenticated;
grant execute on function public.leave_study_group(text) to authenticated;
grant execute on function public.remove_study_group_member(text, text, text) to authenticated;
grant execute on function public.set_study_group_role(text, text, text) to authenticated;
grant execute on function public.set_study_group_admin(text, text, boolean) to authenticated;
grant execute on function public.invite_study_group_member(text, text, text) to authenticated;
grant execute on function public.create_study_group_reading_plan(jsonb) to authenticated;
grant execute on function public.mark_study_assignment_complete(uuid, text) to authenticated;
grant execute on function public.create_study_group_announcement(jsonb) to authenticated;
grant execute on function public.moderate_study_group_message(text, text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
