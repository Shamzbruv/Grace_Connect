-- Church registration and membership approval foundation.
-- This migration keeps legacy placeId/profile fields for compatibility, but
-- makes approved church membership the canonical access signal.

create extension if not exists pgcrypto;

do $$
begin
  create type public.church_registration_status as enum (
    'submitted',
    'under_review',
    'needs_information',
    'approved',
    'rejected',
    'withdrawn'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.church_live_status as enum (
    'approved',
    'suspended',
    'archived'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.church_membership_status as enum (
    'none',
    'pending',
    'active',
    'declined',
    'removed',
    'left',
    'cancelled'
  );
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.grace_account_status as enum (
    'active',
    'suspended',
    'disabled',
    'deleted'
  );
exception when duplicate_object then null;
end $$;

create table if not exists public.denominations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  is_active boolean not null default true,
  naming_rule text,
  approval_mode text not null default 'manual',
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

insert into public.denominations (code, display_name, naming_rule, sort_order)
values
  ('ntcog', 'New Testament Church of God', '{Location Name} NTCOG', 10),
  ('cog_jamaica', 'Church of God in Jamaica', null, 20),
  ('sda', 'Seventh-day Adventist Church', null, 30),
  ('baptist', 'Baptist', null, 40),
  ('methodist', 'Methodist', null, 50),
  ('anglican', 'Anglican', null, 60),
  ('pentecostal', 'Pentecostal', null, 70),
  ('apostolic', 'Apostolic', null, 80),
  ('independent', 'Independent / Non-denominational', null, 90),
  ('other', 'Other', null, 100)
on conflict (code) do update
  set display_name = excluded.display_name,
      naming_rule = excluded.naming_rule,
      sort_order = excluded.sort_order,
      is_active = true;

alter table public.churches
  add column if not exists display_name text,
  add column if not exists legal_name text,
  add column if not exists location_name text,
  add column if not exists denomination_id uuid references public.denominations(id),
  add column if not exists denomination_label text,
  add column if not exists parish text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists church_status text not null default 'suspended',
  add column if not exists owner_user_id uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists public_visibility boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

update public.churches
set display_name = coalesce(nullif(display_name, ''), nullif(name, ''), "placeId", id),
    legal_name = coalesce(nullif(legal_name, ''), nullif(name, ''), display_name),
    denomination_label = coalesce(nullif(denomination_label, ''), nullif(denomination, '')),
    church_status = case
      when lower(coalesce(church_status, '')) = 'approved' then 'approved'
      when lower(coalesce(status, '')) in ('active', 'approved', 'verified') then 'approved'
      when lower(coalesce(status, '')) in ('archived') then 'archived'
      else coalesce(nullif(church_status, ''), 'suspended')
    end,
    public_visibility = case
      when lower(coalesce(status, '')) in ('active', 'approved', 'verified') then true
      else public_visibility
    end,
    approved_at = case
      when lower(coalesce(status, '')) in ('active', 'approved', 'verified') then coalesce(approved_at, "createdAt", now())
      else approved_at
    end
where display_name is null
   or legal_name is null
   or denomination_label is null
   or church_status = 'suspended';

create index if not exists churches_status_visibility_idx
  on public.churches (church_status, public_visibility);

create index if not exists churches_place_id_idx
  on public.churches ("placeId");

create table if not exists public.policy_documents (
  id uuid primary key default gen_random_uuid(),
  document_key text not null,
  title text not null,
  document_version text not null,
  content_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (document_key, document_version)
);

create table if not exists public.policy_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  document_key text not null,
  document_version text not null,
  accepted_at timestamptz not null default now(),
  source text not null default 'app',
  ip_or_device_metadata jsonb not null default '{}'::jsonb,
  unique (user_id, document_key, document_version)
);

create table if not exists public.church_registration_requests (
  id uuid primary key default gen_random_uuid(),
  requested_by_user_id uuid not null references auth.users(id) on delete cascade,
  church_name_submitted text not null,
  location_name text,
  address text,
  parish text,
  denomination_id uuid references public.denominations(id),
  custom_denomination_name text,
  pastor_name text,
  pastor_email text,
  pastor_phone text,
  application_status text not null default 'submitted',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  legal_acceptance_id uuid references public.policy_acceptances(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint church_registration_requests_status_check check (
    application_status in (
      'submitted',
      'under_review',
      'needs_information',
      'approved',
      'rejected',
      'withdrawn'
    )
  )
);

create index if not exists church_registration_requests_status_idx
  on public.church_registration_requests (application_status, created_at desc);

create index if not exists church_registration_requests_user_idx
  on public.church_registration_requests (requested_by_user_id, created_at desc);

create table if not exists public.church_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  church_id text not null,
  membership_status text not null default 'pending',
  requested_at timestamptz not null default now(),
  request_message text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  decision_reason text,
  removed_by uuid references auth.users(id) on delete set null,
  removed_at timestamptz,
  removal_reason text,
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint church_memberships_status_check check (
    membership_status in (
      'none',
      'pending',
      'active',
      'declined',
      'removed',
      'left',
      'cancelled'
    )
  )
);

create unique index if not exists church_memberships_one_active_per_user_idx
  on public.church_memberships (user_id)
  where membership_status = 'active';

create unique index if not exists church_memberships_one_open_request_idx
  on public.church_memberships (user_id, church_id)
  where membership_status in ('pending', 'active');

create index if not exists church_memberships_church_status_idx
  on public.church_memberships (church_id, membership_status, requested_at desc);

create table if not exists public.church_member_roles (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.church_memberships(id) on delete cascade,
  role_name text not null,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (membership_id, role_name)
);

create table if not exists public.church_approval_audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  target_user_id uuid references auth.users(id) on delete set null,
  church_id text,
  event_type text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists church_approval_audit_events_church_idx
  on public.church_approval_audit_events (church_id, created_at desc);

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_church_registration_requests_updated_at on public.church_registration_requests;
create trigger touch_church_registration_requests_updated_at
  before update on public.church_registration_requests
  for each row execute function public.touch_updated_at();

drop trigger if exists touch_church_memberships_updated_at on public.church_memberships;
create trigger touch_church_memberships_updated_at
  before update on public.church_memberships
  for each row execute function public.touch_updated_at();

create or replace function public.is_approved_church(target_church_id text)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.churches c
    where (c.id = target_church_id or c."placeId" = target_church_id)
      and c.church_status = 'approved'
      and c.public_visibility = true
  );
$$;

create or replace function public.is_active_member_of(target_church_id text)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.church_memberships cm
    join public.churches c
      on c.id = cm.church_id
      or c."placeId" = cm.church_id
    where cm.user_id = auth.uid()
      and cm.church_id = target_church_id
      and cm.membership_status = 'active'
      and c.church_status = 'approved'
      and c.public_visibility = true
  );
$$;

create or replace function public.current_active_church_id()
returns text
language sql
security definer
set search_path to 'public'
as $$
  select cm.church_id
  from public.church_memberships cm
  join public.churches c
    on c.id = cm.church_id
    or c."placeId" = cm.church_id
  where cm.user_id = auth.uid()
    and cm.membership_status = 'active'
    and c.church_status = 'approved'
    and c.public_visibility = true
  order by cm.reviewed_at desc nulls last, cm.created_at desc
  limit 1;
$$;

create or replace function public.get_church_id()
returns text
language sql
security definer
set search_path to 'public'
as $$
  select public.current_active_church_id();
$$;

create or replace function public.can_review_church_registrations()
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.users u
    left join unnest(coalesce(u.roles, '{}'::text[])) as user_role(role_name) on true
    where u.id = auth.uid()
      and (
        coalesce(u."isDeveloper", false) = true
        or public.normalize_role_name(user_role.role_name) in (
          'platform_admin',
          'grace_connect_admin',
          'super_admin'
        )
      )
  );
$$;

create or replace function public.can_manage_church_members(target_church_id text)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select public.is_active_member_of(target_church_id)
    and exists (
      select 1
      from public.users u
      left join unnest(coalesce(u.roles, '{}'::text[])) as user_role(role_name) on true
      where u.id = auth.uid()
        and public.normalize_role_name(user_role.role_name) in (
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'church_admin',
          'admin',
          'administrator',
          'secretary',
          'church_secretary'
        )
    );
$$;

create or replace function public.has_any_role(required_roles text[])
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select public.current_active_church_id() is not null
    and exists (
      select 1
      from public.users u
      cross join unnest(coalesce(u.roles, '{}'::text[])) as user_role(role_name)
      where u.id = auth.uid()
        and public.normalize_role_name(user_role.role_name) = any (
          select public.normalize_role_name(required_role)
          from unnest(required_roles) as required_role
        )
    );
$$;

create or replace function public.get_public_church_directory(search_query text default null)
returns table (
  id text,
  "placeId" text,
  name text,
  address text,
  parish text,
  denomination text
)
language sql
security definer
set search_path to 'public'
as $$
  select
    coalesce(c.id, c."placeId")::text as id,
    coalesce(c."placeId", c.id)::text as "placeId",
    coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId", c.id)::text as name,
    coalesce(c.address, '')::text as address,
    coalesce(c.parish, '')::text as parish,
    coalesce(c.denomination_label, c.denomination, '')::text as denomination
  from public.churches c
  where c.church_status = 'approved'
    and c.public_visibility = true
    and (
      nullif(trim(coalesce(search_query, '')), '') is null
      or coalesce(c.display_name, c.name, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.address, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.parish, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.denomination_label, c.denomination, '') ilike '%' || trim(search_query) || '%'
    )
  order by name
  limit 25;
$$;

create or replace function public.request_church_membership(
  target_church_id text,
  request_note text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  clean_church_id text := nullif(trim(target_church_id), '');
  inserted_id uuid;
  church_name text;
  leader record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if clean_church_id is null then
    raise exception 'Please select a church.';
  end if;

  select coalesce(nullif(display_name, ''), nullif(name, ''), "placeId", id)
    into church_name
  from public.churches
  where (id = clean_church_id or "placeId" = clean_church_id)
    and church_status = 'approved'
    and public_visibility = true
  limit 1;

  if church_name is null then
    raise exception 'This church is not approved for membership requests.';
  end if;

  if exists (
    select 1
    from public.church_memberships
    where user_id = actor_id
      and membership_status = 'active'
  ) then
    raise exception 'You already have an active church membership.';
  end if;

  insert into public.church_memberships (
    user_id,
    church_id,
    membership_status,
    request_message
  )
  values (
    actor_id,
    clean_church_id,
    'pending',
    nullif(trim(coalesce(request_note, '')), '')
  )
  on conflict (user_id, church_id)
    where membership_status in ('pending', 'active')
  do update
    set membership_status = 'pending',
        request_message = excluded.request_message,
        requested_at = now(),
        reviewed_by = null,
        reviewed_at = null,
        decision_reason = null,
        removed_by = null,
        removed_at = null,
        removal_reason = null,
        left_at = null
  returning id into inserted_id;

  update public.users
  set "accountState" = 'pending',
      "placeId" = null,
      "placeName" = null,
      roles = array['Member']
  where id = actor_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    clean_church_id,
    'membership_requested',
    jsonb_build_object('churchName', church_name)
  );

  for leader in
    select u.id
    from public.users u
    cross join unnest(coalesce(u.roles, '{}'::text[])) as role_name
    where u."placeId" = clean_church_id
      and public.normalize_role_name(role_name) in (
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor',
        'church_admin',
        'admin',
        'administrator',
        'secretary',
        'church_secretary'
      )
      and exists (
        select 1
        from public.church_memberships cm
        where cm.user_id = u.id
          and cm.church_id = clean_church_id
          and cm.membership_status = 'active'
      )
  loop
    begin
      perform public.create_notification(
        leader.id,
        actor_id,
        'membership_request_received',
        'New membership request',
        'A member requested to join ' || church_name || '.',
        clean_church_id,
        'church_memberships',
        inserted_id::text,
        '/members'
      );
    exception when undefined_function then
      null;
    end;
  end loop;

  return inserted_id;
end;
$$;

create or replace function public.approve_church_membership(
  membership_id uuid,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target record;
  church_name text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target
  from public.church_memberships
  where id = membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.user_id = actor_id then
    raise exception 'You cannot approve your own membership.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be approved.';
  end if;

  if not public.can_manage_church_members(target.church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  update public.church_memberships
  set membership_status = 'active',
      reviewed_by = actor_id,
      reviewed_at = now(),
      decision_reason = nullif(trim(coalesce(decision_note, '')), '')
  where id = membership_id;

  update public.church_memberships
  set membership_status = 'cancelled',
      decision_reason = 'Cancelled because another church membership was approved.'
  where user_id = target.user_id
    and id <> membership_id
    and membership_status = 'pending';

  select coalesce(nullif(display_name, ''), nullif(name, ''), target.church_id)
    into church_name
  from public.churches
  where id = target.church_id or "placeId" = target.church_id
  limit 1;

  update public.users
  set "placeId" = target.church_id,
      "placeName" = coalesce(church_name, target.church_id),
      "accountState" = 'active',
      roles = case
        when roles is null or array_length(roles, 1) is null then array['Member']
        else roles
      end
  where id = target.user_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    target.user_id,
    target.church_id,
    'membership_approved',
    jsonb_build_object('reason', nullif(trim(coalesce(decision_note, '')), ''))
  );

  begin
    perform public.create_notification(
      target.user_id,
      actor_id,
      'membership_approved',
      'Membership approved',
      'Your request to join ' || coalesce(church_name, 'this church') || ' was approved.',
      target.church_id,
      'church_memberships',
      membership_id::text,
      '/dashboard'
    );
  exception when undefined_function then
    null;
  end;
end;
$$;

create or replace function public.decline_church_membership(
  membership_id uuid,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target
  from public.church_memberships
  where id = membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.user_id = actor_id then
    raise exception 'You cannot decline your own membership.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be declined.';
  end if;

  if not public.can_manage_church_members(target.church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  update public.church_memberships
  set membership_status = 'declined',
      reviewed_by = actor_id,
      reviewed_at = now(),
      decision_reason = nullif(trim(coalesce(decision_note, '')), '')
  where id = membership_id;

  update public.users
  set "accountState" = 'declined',
      "placeId" = null,
      "placeName" = null,
      roles = array['Member']
  where id = target.user_id
    and not exists (
      select 1
      from public.church_memberships
      where user_id = target.user_id
        and membership_status = 'active'
    );

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    target.user_id,
    target.church_id,
    'membership_declined',
    jsonb_build_object('reason', nullif(trim(coalesce(decision_note, '')), ''))
  );

  begin
    perform public.create_notification(
      target.user_id,
      actor_id,
      'membership_declined',
      'Membership request declined',
      'Your church membership request was declined.',
      target.church_id,
      'church_memberships',
      membership_id::text,
      '/'
    );
  exception when undefined_function then
    null;
  end;
end;
$$;

create or replace function public.remove_church_member(
  target_user_id uuid,
  target_church_id text,
  removal_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  active_owner_count integer;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if actor_id = target_user_id then
    raise exception 'Use leave_church to leave your own church.';
  end if;

  if not public.can_manage_church_members(target_church_id) then
    raise exception 'You cannot remove members from this church.';
  end if;

  if exists (
    select 1
    from public.churches
    where (id = target_church_id or "placeId" = target_church_id)
      and owner_user_id = target_user_id
  ) then
    select count(*)
      into active_owner_count
    from public.church_memberships cm
    join public.churches c
      on c.owner_user_id = cm.user_id
     and (c.id = cm.church_id or c."placeId" = cm.church_id)
    where cm.church_id = target_church_id
      and cm.membership_status = 'active';

    if active_owner_count <= 1 then
      raise exception 'Transfer ownership before removing the final active church owner.';
    end if;
  end if;

  update public.church_memberships
  set membership_status = 'removed',
      removed_by = actor_id,
      removed_at = now(),
      removal_reason = nullif(trim(coalesce(removal_note, '')), '')
  where user_id = target_user_id
    and church_id = target_church_id
    and membership_status = 'active';

  update public.users
  set "accountState" = 'removed',
      "placeId" = null,
      "placeName" = null,
      roles = array['Member']
  where id = target_user_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    target_user_id,
    target_church_id,
    'membership_removed',
    jsonb_build_object('reason', nullif(trim(coalesce(removal_note, '')), ''))
  );
end;
$$;

create or replace function public.leave_church()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  active_church text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  active_church := public.current_active_church_id();

  if active_church is null then
    return;
  end if;

  update public.church_memberships
  set membership_status = 'left',
      left_at = now()
  where user_id = actor_id
    and church_id = active_church
    and membership_status = 'active';

  update public.users
  set "accountState" = 'active',
      "placeId" = null,
      "placeName" = null,
      roles = array['Member']
  where id = actor_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type
  )
  values (actor_id, actor_id, active_church, 'membership_left');
end;
$$;

create or replace function public.get_current_membership_context()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  profile record;
  membership record;
  active_application record;
begin
  if actor_id is null then
    return jsonb_build_object('authenticated', false);
  end if;

  select *
    into profile
  from public.users
  where id = actor_id or uid = actor_id::text
  limit 1;

  select cm.*,
         coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id) as church_name,
         c.church_status
    into membership
  from public.church_memberships cm
  left join public.churches c
    on c.id = cm.church_id
    or c."placeId" = cm.church_id
  where cm.user_id = actor_id
  order by
    case cm.membership_status
      when 'active' then 1
      when 'pending' then 2
      when 'declined' then 3
      when 'removed' then 4
      else 5
    end,
    cm.updated_at desc
  limit 1;

  select *
    into active_application
  from public.church_registration_requests
  where requested_by_user_id = actor_id
    and application_status in (
      'submitted',
      'under_review',
      'needs_information'
    )
  order by created_at desc
  limit 1;

  return jsonb_build_object(
    'authenticated', true,
    'hasProfile', profile.id is not null,
    'accountStatus', coalesce(nullif(profile."accountState", ''), 'active'),
    'membershipStatus', coalesce(membership.membership_status, 'none'),
    'membershipId', membership.id,
    'churchId', membership.church_id,
    'churchName', membership.church_name,
    'churchStatus', membership.church_status,
    'requestedAt', membership.requested_at,
    'reviewedAt', membership.reviewed_at,
    'decisionReason', membership.decision_reason,
    'hasPendingChurchApplication', active_application.id is not null,
    'churchApplicationStatus', active_application.application_status
  );
end;
$$;

create or replace function public.submit_church_registration(
  church_name text,
  location text default null,
  church_address text default null,
  church_parish text default null,
  denomination uuid default null,
  custom_denomination text default null,
  pastor_full_name text default null,
  pastor_contact_email text default null,
  pastor_contact_phone text default null,
  legal_acceptance uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  inserted_id uuid;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if nullif(trim(coalesce(church_name, '')), '') is null then
    raise exception 'Church name is required.';
  end if;

  insert into public.church_registration_requests (
    requested_by_user_id,
    church_name_submitted,
    location_name,
    address,
    parish,
    denomination_id,
    custom_denomination_name,
    pastor_name,
    pastor_email,
    pastor_phone,
    legal_acceptance_id
  )
  values (
    actor_id,
    trim(church_name),
    nullif(trim(coalesce(location, '')), ''),
    nullif(trim(coalesce(church_address, '')), ''),
    nullif(trim(coalesce(church_parish, '')), ''),
    denomination,
    nullif(trim(coalesce(custom_denomination, '')), ''),
    nullif(trim(coalesce(pastor_full_name, '')), ''),
    nullif(trim(coalesce(pastor_contact_email, '')), ''),
    nullif(trim(coalesce(pastor_contact_phone, '')), ''),
    legal_acceptance
  )
  returning id into inserted_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    'church_registration_submitted',
    jsonb_build_object('requestId', inserted_id, 'churchName', trim(church_name))
  );

  return inserted_id;
end;
$$;

create or replace function public.approve_church_registration(
  request_id uuid,
  review_note text default null
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  request_row record;
  denom record;
  church_place_id text;
  final_name text;
begin
  if actor_id is null or not public.can_review_church_registrations() then
    raise exception 'Only platform reviewers can approve church registrations.';
  end if;

  select *
    into request_row
  from public.church_registration_requests
  where id = request_id
  for update;

  if request_row.id is null then
    raise exception 'Church registration request not found.';
  end if;

  if request_row.application_status = 'approved' then
    raise exception 'This church registration is already approved.';
  end if;

  select *
    into denom
  from public.denominations
  where id = request_row.denomination_id;

  final_name := request_row.church_name_submitted;
  if denom.code = 'ntcog' and nullif(trim(coalesce(request_row.location_name, '')), '') is not null then
    final_name := trim(request_row.location_name) || ' NTCOG';
  end if;

  church_place_id := 'church_' || replace(gen_random_uuid()::text, '-', '');

  insert into public.churches (
    id,
    "placeId",
    name,
    display_name,
    legal_name,
    location_name,
    denomination_id,
    denomination_label,
    address,
    parish,
    "ownerUserId",
    owner_user_id,
    timezone,
    status,
    church_status,
    approved_at,
    approved_by,
    public_visibility,
    "createdAt",
    updated_at
  )
  values (
    church_place_id,
    church_place_id,
    final_name,
    final_name,
    request_row.church_name_submitted,
    request_row.location_name,
    request_row.denomination_id,
    coalesce(denom.display_name, request_row.custom_denomination_name),
    request_row.address,
    request_row.parish,
    request_row.requested_by_user_id::text,
    request_row.requested_by_user_id,
    'America/Jamaica',
    'active',
    'approved',
    now(),
    actor_id,
    true,
    now(),
    now()
  );

  update public.church_registration_requests
  set application_status = 'approved',
      reviewed_by = actor_id,
      reviewed_at = now(),
      review_notes = nullif(trim(coalesce(review_note, '')), '')
  where id = request_id;

  insert into public.church_memberships (
    user_id,
    church_id,
    membership_status,
    reviewed_by,
    reviewed_at,
    decision_reason
  )
  values (
    request_row.requested_by_user_id,
    church_place_id,
    'active',
    actor_id,
    now(),
    'Initial leader approved with church registration.'
  )
  on conflict (user_id)
    where membership_status = 'active'
  do nothing;

  update public.users
  set "placeId" = church_place_id,
      "placeName" = final_name,
      "accountState" = 'active',
      roles = array['Admin', 'Pastor']
  where id = request_row.requested_by_user_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    request_row.requested_by_user_id,
    church_place_id,
    'church_registration_approved',
    jsonb_build_object('requestId', request_id, 'reviewNote', nullif(trim(coalesce(review_note, '')), ''))
  );

  return church_place_id;
end;
$$;

create or replace function public.reject_church_registration(
  request_id uuid,
  review_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  request_row record;
begin
  if actor_id is null or not public.can_review_church_registrations() then
    raise exception 'Only platform reviewers can reject church registrations.';
  end if;

  select *
    into request_row
  from public.church_registration_requests
  where id = request_id
  for update;

  if request_row.id is null then
    raise exception 'Church registration request not found.';
  end if;

  update public.church_registration_requests
  set application_status = 'rejected',
      reviewed_by = actor_id,
      reviewed_at = now(),
      review_notes = nullif(trim(coalesce(review_note, '')), '')
  where id = request_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    event_type,
    details
  )
  values (
    actor_id,
    request_row.requested_by_user_id,
    'church_registration_rejected',
    jsonb_build_object('requestId', request_id, 'reviewNote', nullif(trim(coalesce(review_note, '')), ''))
  );
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  profile_phone text := nullif(coalesce(meta->>'phone', meta->>'phoneNumber'), '');
begin
  insert into public.users (
    id,
    uid,
    email,
    "fullName",
    phone,
    "placeId",
    "placeName",
    roles,
    "joinDate",
    "photoUrl",
    bio,
    "isDeveloper",
    "accountState"
  )
  values (
    new.id,
    new.id::text,
    coalesce(new.email, ''),
    coalesce(
      nullif(meta->>'fullName', ''),
      nullif(meta->>'full_name', ''),
      nullif(meta->>'name', ''),
      split_part(coalesce(new.email, 'Member'), '@', 1)
    ),
    profile_phone,
    null,
    null,
    array['Member'],
    now(),
    coalesce(nullif(meta->>'avatar_url', ''), ''),
    coalesce(nullif(meta->>'bio', ''), ''),
    false,
    'active'
  )
  on conflict (uid) do update
    set email = excluded.email,
        "fullName" = coalesce(nullif(excluded."fullName", ''), public.users."fullName"),
        phone = coalesce(excluded.phone, public.users.phone),
        roles = case
          when public.users.roles is null or array_length(public.users.roles, 1) is null then array['Member']
          else public.users.roles
        end,
        "accountState" = case
          when public.users."accountState" in ('suspended', 'disabled', 'deleted', 'deletion_requested') then public.users."accountState"
          else coalesce(public.users."accountState", 'active')
        end;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

alter table public.denominations enable row level security;
alter table public.policy_documents enable row level security;
alter table public.policy_acceptances enable row level security;
alter table public.church_registration_requests enable row level security;
alter table public.church_memberships enable row level security;
alter table public.church_member_roles enable row level security;
alter table public.church_approval_audit_events enable row level security;

drop policy if exists "Anyone can view active denominations" on public.denominations;
create policy "Anyone can view active denominations"
  on public.denominations
  for select
  to anon, authenticated
  using (is_active = true);

drop policy if exists "Anyone can view active policy documents" on public.policy_documents;
create policy "Anyone can view active policy documents"
  on public.policy_documents
  for select
  to anon, authenticated
  using (is_active = true);

drop policy if exists "Users view own policy acceptances" on public.policy_acceptances;
create policy "Users view own policy acceptances"
  on public.policy_acceptances
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users create own policy acceptances" on public.policy_acceptances;
create policy "Users create own policy acceptances"
  on public.policy_acceptances
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users view own church registration requests" on public.church_registration_requests;
create policy "Users view own church registration requests"
  on public.church_registration_requests
  for select
  to authenticated
  using (
    requested_by_user_id = auth.uid()
    or public.can_review_church_registrations()
  );

drop policy if exists "Users create own church registration requests" on public.church_registration_requests;
create policy "Users create own church registration requests"
  on public.church_registration_requests
  for insert
  to authenticated
  with check (requested_by_user_id = auth.uid());

drop policy if exists "Reviewers update church registration requests" on public.church_registration_requests;
create policy "Reviewers update church registration requests"
  on public.church_registration_requests
  for update
  to authenticated
  using (public.can_review_church_registrations())
  with check (public.can_review_church_registrations());

drop policy if exists "Members view relevant memberships" on public.church_memberships;
create policy "Members view relevant memberships"
  on public.church_memberships
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.can_manage_church_members(church_id)
  );

drop policy if exists "Members create own pending membership" on public.church_memberships;
create policy "Members create own pending membership"
  on public.church_memberships
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and membership_status = 'pending'
    and public.is_approved_church(church_id)
  );

drop policy if exists "Church leaders update membership decisions" on public.church_memberships;
create policy "Church leaders update membership decisions"
  on public.church_memberships
  for update
  to authenticated
  using (
    user_id = auth.uid()
    or public.can_manage_church_members(church_id)
  )
  with check (
    user_id = auth.uid()
    or public.can_manage_church_members(church_id)
  );

drop policy if exists "Leaders view church member roles" on public.church_member_roles;
create policy "Leaders view church member roles"
  on public.church_member_roles
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.church_memberships cm
      where cm.id = membership_id
        and (
          cm.user_id = auth.uid()
          or public.can_manage_church_members(cm.church_id)
        )
    )
  );

drop policy if exists "Reviewers and leaders view approval audit events" on public.church_approval_audit_events;
create policy "Reviewers and leaders view approval audit events"
  on public.church_approval_audit_events
  for select
  to authenticated
  using (
    public.can_review_church_registrations()
    or target_user_id = auth.uid()
    or (
      church_id is not null
      and public.can_manage_church_members(church_id)
    )
  );

drop policy if exists "Public approved church directory" on public.churches;
create policy "Public approved church directory"
  on public.churches
  for select
  to anon, authenticated
  using (church_status = 'approved' and public_visibility = true);

grant execute on function public.is_active_member_of(text) to authenticated;
grant execute on function public.current_active_church_id() to authenticated;
grant execute on function public.can_manage_church_members(text) to authenticated;
grant execute on function public.can_review_church_registrations() to authenticated;
grant execute on function public.get_current_membership_context() to authenticated;
grant execute on function public.get_public_church_directory(text) to anon, authenticated;
grant execute on function public.request_church_membership(text, text) to authenticated;
grant execute on function public.approve_church_membership(uuid, text) to authenticated;
grant execute on function public.decline_church_membership(uuid, text) to authenticated;
grant execute on function public.remove_church_member(uuid, text, text) to authenticated;
grant execute on function public.leave_church() to authenticated;
grant execute on function public.submit_church_registration(text, text, text, text, uuid, text, text, text, text, uuid) to authenticated;
grant execute on function public.approve_church_registration(uuid, text) to authenticated;
grant execute on function public.reject_church_registration(uuid, text) to authenticated;
