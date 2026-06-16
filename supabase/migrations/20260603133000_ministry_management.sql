-- Ministry management: pastors create ministries, assign managers, and allow
-- managers to publish ministry announcements/events.

create table if not exists public.ministries (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  name text not null,
  description text not null default '',
  status text not null default 'active'
    check (status in ('active', 'archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ministries_church_name_active_idx
  on public.ministries (church_id, lower(name))
  where status = 'active';

create index if not exists ministries_church_status_idx
  on public.ministries (church_id, status, name);

create table if not exists public.ministry_managers (
  id uuid primary key default gen_random_uuid(),
  ministry_id uuid not null references public.ministries(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_title text not null default 'Ministry Manager',
  can_create_events boolean not null default true,
  can_publish_announcements boolean not null default true,
  assigned_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  revoked_at timestamptz
);

create unique index if not exists ministry_managers_active_user_idx
  on public.ministry_managers (ministry_id, user_id)
  where revoked_at is null;

create index if not exists ministry_managers_user_active_idx
  on public.ministry_managers (user_id, revoked_at);

alter table public.events
  add column if not exists ministry_id uuid references public.ministries(id)
    on delete set null,
  add column if not exists ministry_name text not null default '';

alter table public.announcements
  add column if not exists ministry_id uuid references public.ministries(id)
    on delete set null,
  add column if not exists ministry_name text not null default '';

create index if not exists events_ministry_idx
  on public.events (ministry_id, date);

create index if not exists announcements_ministry_idx
  on public.announcements (ministry_id, created_at desc)
  where deleted_at is null;

create or replace function public.can_manage_ministry_setup()
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select public.has_any_role(array['Pastor', 'Senior Pastor']);
$$;

create or replace function public.is_ministry_manager(
  target_church_id text default null,
  target_ministry_id uuid default null,
  required_capability text default null
)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.ministry_managers mm
    join public.ministries m on m.id = mm.ministry_id
    where mm.user_id = auth.uid()
      and mm.revoked_at is null
      and m.status = 'active'
      and (
        target_church_id is null
        or m.church_id = target_church_id
      )
      and (
        target_ministry_id is null
        or mm.ministry_id = target_ministry_id
      )
      and (
        required_capability is null
        or (required_capability = 'events' and mm.can_create_events)
        or (
          required_capability = 'announcements'
          and mm.can_publish_announcements
        )
      )
  );
$$;

create or replace function public.set_ministry_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_set_ministry_updated_at on public.ministries;
create trigger trg_set_ministry_updated_at
  before update on public.ministries
  for each row execute function public.set_ministry_updated_at();

create or replace function public.create_ministry(
  ministry_name text,
  ministry_description text default ''
)
returns public.ministries
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_church_id text := public.get_church_id();
  inserted_ministry public.ministries;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_manage_ministry_setup() then
    raise exception 'Only the pastor or senior pastor can create ministries';
  end if;

  if actor_church_id is null or trim(actor_church_id) = '' then
    raise exception 'Join a church before creating ministries';
  end if;

  insert into public.ministries (
    church_id,
    name,
    description,
    created_by
  )
  values (
    actor_church_id,
    trim(ministry_name),
    trim(coalesce(ministry_description, '')),
    auth.uid()
  )
  returning * into inserted_ministry;

  return inserted_ministry;
end;
$$;

create or replace function public.assign_ministry_manager(
  target_ministry_id uuid,
  target_user_id uuid,
  manager_role_title text default 'Ministry Manager',
  allow_events boolean default true,
  allow_announcements boolean default true
)
returns public.ministry_managers
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_church_id text := public.get_church_id();
  target_ministry public.ministries;
  target_member public.users;
  active_assignment public.ministry_managers;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_manage_ministry_setup() then
    raise exception 'Only the pastor or senior pastor can assign ministry managers';
  end if;

  select *
    into target_ministry
    from public.ministries
    where id = target_ministry_id
      and church_id = actor_church_id;

  if target_ministry.id is null then
    raise exception 'Ministry not found for your church';
  end if;

  select *
    into target_member
    from public.users
    where id = target_user_id
      and "placeId" = target_ministry.church_id;

  if target_member.id is null then
    raise exception 'Member not found in this church';
  end if;

  select *
    into active_assignment
    from public.ministry_managers
    where ministry_id = target_ministry_id
      and user_id = target_user_id
      and revoked_at is null
    limit 1;

  if active_assignment.id is not null then
    update public.ministry_managers
    set role_title = coalesce(nullif(trim(manager_role_title), ''), 'Ministry Manager'),
        can_create_events = allow_events,
        can_publish_announcements = allow_announcements,
        assigned_by = auth.uid(),
        assigned_at = now()
    where id = active_assignment.id
    returning * into active_assignment;

    return active_assignment;
  end if;

  insert into public.ministry_managers (
    ministry_id,
    user_id,
    role_title,
    can_create_events,
    can_publish_announcements,
    assigned_by
  )
  values (
    target_ministry_id,
    target_user_id,
    coalesce(nullif(trim(manager_role_title), ''), 'Ministry Manager'),
    allow_events,
    allow_announcements,
    auth.uid()
  )
  returning * into active_assignment;

  return active_assignment;
end;
$$;

create or replace function public.revoke_ministry_manager(
  manager_assignment_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_church_id text := public.get_church_id();
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.can_manage_ministry_setup() then
    raise exception 'Only the pastor or senior pastor can remove ministry managers';
  end if;

  update public.ministry_managers mm
  set revoked_at = now()
  from public.ministries m
  where mm.id = manager_assignment_id
    and mm.ministry_id = m.id
    and m.church_id = actor_church_id
    and mm.revoked_at is null;
end;
$$;

create or replace function public.get_ministry_managers(
  target_ministry_id uuid
)
returns table (
  id uuid,
  ministry_id uuid,
  ministry_name text,
  user_id uuid,
  user_name text,
  user_email text,
  user_photo_url text,
  role_title text,
  can_create_events boolean,
  can_publish_announcements boolean,
  assigned_by uuid,
  assigned_at timestamptz,
  revoked_at timestamptz
)
language sql
security definer
set search_path to 'public'
as $$
  select
    mm.id,
    mm.ministry_id,
    m.name as ministry_name,
    mm.user_id,
    coalesce(nullif(u."fullName", ''), nullif(u.email, ''), 'Member') as user_name,
    coalesce(u.email, '') as user_email,
    coalesce(u."photoUrl", '') as user_photo_url,
    mm.role_title,
    mm.can_create_events,
    mm.can_publish_announcements,
    mm.assigned_by,
    mm.assigned_at,
    mm.revoked_at
  from public.ministry_managers mm
  join public.ministries m on m.id = mm.ministry_id
  join public.users u on u.id = mm.user_id
  where mm.ministry_id = target_ministry_id
    and m.church_id = public.get_church_id()
  order by mm.revoked_at nulls first, mm.assigned_at desc;
$$;

create or replace function public.get_my_managed_ministries()
returns table (
  id uuid,
  ministry_id uuid,
  ministry_name text,
  user_id uuid,
  user_name text,
  user_email text,
  user_photo_url text,
  role_title text,
  can_create_events boolean,
  can_publish_announcements boolean,
  assigned_by uuid,
  assigned_at timestamptz,
  revoked_at timestamptz
)
language sql
security definer
set search_path to 'public'
as $$
  select
    mm.id,
    mm.ministry_id,
    m.name as ministry_name,
    mm.user_id,
    coalesce(nullif(u."fullName", ''), nullif(u.email, ''), 'Member') as user_name,
    coalesce(u.email, '') as user_email,
    coalesce(u."photoUrl", '') as user_photo_url,
    mm.role_title,
    mm.can_create_events,
    mm.can_publish_announcements,
    mm.assigned_by,
    mm.assigned_at,
    mm.revoked_at
  from public.ministry_managers mm
  join public.ministries m on m.id = mm.ministry_id
  join public.users u on u.id = mm.user_id
  where mm.user_id = auth.uid()
    and mm.revoked_at is null
    and m.status = 'active'
    and m.church_id = public.get_church_id()
  order by m.name;
$$;

alter table public.ministries enable row level security;
alter table public.ministry_managers enable row level security;

drop policy if exists "Church members view ministries" on public.ministries;
create policy "Church members view ministries"
  on public.ministries
  for select
  to authenticated
  using (church_id = public.get_church_id());

drop policy if exists "Pastors insert ministries" on public.ministries;
create policy "Pastors insert ministries"
  on public.ministries
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and public.can_manage_ministry_setup()
  );

drop policy if exists "Pastors update ministries" on public.ministries;
create policy "Pastors update ministries"
  on public.ministries
  for update
  to authenticated
  using (
    church_id = public.get_church_id()
    and public.can_manage_ministry_setup()
  )
  with check (
    church_id = public.get_church_id()
    and public.can_manage_ministry_setup()
  );

drop policy if exists "Church members view ministry managers" on public.ministry_managers;
create policy "Church members view ministry managers"
  on public.ministry_managers
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.ministries m
      where m.id = ministry_id
        and m.church_id = public.get_church_id()
    )
  );

drop policy if exists "Pastors insert ministry managers" on public.ministry_managers;
create policy "Pastors insert ministry managers"
  on public.ministry_managers
  for insert
  to authenticated
  with check (
    public.can_manage_ministry_setup()
    and exists (
      select 1
      from public.ministries m
      where m.id = ministry_id
        and m.church_id = public.get_church_id()
    )
  );

drop policy if exists "Pastors update ministry managers" on public.ministry_managers;
create policy "Pastors update ministry managers"
  on public.ministry_managers
  for update
  to authenticated
  using (
    public.can_manage_ministry_setup()
    and exists (
      select 1
      from public.ministries m
      where m.id = ministry_id
        and m.church_id = public.get_church_id()
    )
  )
  with check (
    public.can_manage_ministry_setup()
    and exists (
      select 1
      from public.ministries m
      where m.id = ministry_id
        and m.church_id = public.get_church_id()
    )
  );

drop policy if exists "Church staff insert events" on public.events;
drop policy if exists "Church staff update events" on public.events;
drop policy if exists "Church staff delete events" on public.events;

create policy "Church staff insert events"
  on public.events
  for insert
  to authenticated
  with check (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Event Coordinator',
        'Ministry Leader'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager("churchId", ministry_id, 'events')
      )
    )
    and (
      ministry_id is null
      or exists (
        select 1
        from public.ministries m
        where m.id = ministry_id
          and m.church_id = "churchId"
      )
    )
  );

create policy "Church staff update events"
  on public.events
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Event Coordinator',
        'Ministry Leader'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager("churchId", ministry_id, 'events')
      )
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Event Coordinator',
        'Ministry Leader'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager("churchId", ministry_id, 'events')
      )
    )
    and (
      ministry_id is null
      or exists (
        select 1
        from public.ministries m
        where m.id = ministry_id
          and m.church_id = "churchId"
      )
    )
  );

create policy "Church staff delete events"
  on public.events
  for delete
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Event Coordinator'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager("churchId", ministry_id, 'events')
      )
    )
  );

drop policy if exists "Announcement publishers insert announcements" on public.announcements;
drop policy if exists "Announcement publishers update announcements" on public.announcements;
drop policy if exists "Announcement publishers delete announcements" on public.announcements;

create policy "Announcement publishers insert announcements"
  on public.announcements
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and author_id = auth.uid()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager(church_id, ministry_id, 'announcements')
      )
    )
    and (
      ministry_id is null
      or exists (
        select 1
        from public.ministries m
        where m.id = ministry_id
          and m.church_id = church_id
      )
    )
  );

create policy "Announcement publishers update announcements"
  on public.announcements
  for update
  to authenticated
  using (
    church_id = public.get_church_id()
    and deleted_at is null
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager(church_id, ministry_id, 'announcements')
      )
    )
  )
  with check (
    church_id = public.get_church_id()
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager(church_id, ministry_id, 'announcements')
      )
    )
    and (
      ministry_id is null
      or exists (
        select 1
        from public.ministries m
        where m.id = ministry_id
          and m.church_id = church_id
      )
    )
  );

create policy "Announcement publishers delete announcements"
  on public.announcements
  for delete
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
      or (
        ministry_id is not null
        and public.is_ministry_manager(church_id, ministry_id, 'announcements')
      )
    )
  );

grant select, insert, update on public.ministries to authenticated;
grant select, insert, update on public.ministry_managers to authenticated;

grant execute on function public.can_manage_ministry_setup() to authenticated;
grant execute on function public.is_ministry_manager(text, uuid, text) to authenticated;
grant execute on function public.create_ministry(text, text) to authenticated;
grant execute on function public.assign_ministry_manager(uuid, uuid, text, boolean, boolean) to authenticated;
grant execute on function public.revoke_ministry_manager(uuid) to authenticated;
grant execute on function public.get_ministry_managers(uuid) to authenticated;
grant execute on function public.get_my_managed_ministries() to authenticated;

alter table public.ministries replica identity full;
alter table public.ministry_managers replica identity full;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ministries'
    ) then
      execute 'alter publication supabase_realtime add table public.ministries';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'ministry_managers'
    ) then
      execute 'alter publication supabase_realtime add table public.ministry_managers';
    end if;
  end if;
exception when undefined_object then
  null;
end;
$$;
