create or replace function public.normalize_role_name(role_name text)
returns text
language sql
immutable
as $$
  select trim(both '_' from regexp_replace(lower(coalesce(role_name, '')), '[^a-z0-9]+', '_', 'g'));
$$;

create or replace function public.has_any_role(required_roles text[])
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
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

alter table public.events
  add column if not exists "sourceLabel" text not null default 'Church Event',
  add column if not exists "createdAt" timestamptz not null default now();

drop policy if exists "Event Coordinators insert events" on public.events;
drop policy if exists "Event Coordinators update events" on public.events;
drop policy if exists "Members update events (for RSVP)" on public.events;
drop policy if exists "Church staff insert events" on public.events;
drop policy if exists "Church staff update events" on public.events;
drop policy if exists "Church staff delete events" on public.events;

create policy "Church staff insert events"
  on public.events
  for insert
  to authenticated
  with check (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
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
  );

create policy "Church staff update events"
  on public.events
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
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
  )
  with check (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
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
  );

create policy "Church staff delete events"
  on public.events
  for delete
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
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
  );

create or replace function public.rsvp_event(target_event_id text, is_joining boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  current_user_id text := auth.uid()::text;
  target_church_id text;
  current_attendees text[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select "churchId", coalesce(attendees, '{}'::text[])
    into target_church_id, current_attendees
  from public.events
  where id = target_event_id;

  if target_church_id is null then
    raise exception 'Event not found';
  end if;

  if target_church_id <> public.get_church_id() then
    raise exception 'You cannot RSVP to an event outside your church';
  end if;

  update public.events
  set attendees = case
    when is_joining then (
      select array_agg(distinct attendee)
      from unnest(current_attendees || current_user_id) as attendee
    )
    else array_remove(current_attendees, current_user_id)
  end
  where id = target_event_id;
end;
$$;

create or replace function public.notify_church_members_on_event()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  member_record record;
  actor_uuid uuid;
  event_date text;
  event_title text;
begin
  if nullif(new."organizerId", '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    actor_uuid := new."organizerId"::uuid;
  end if;

  event_date := coalesce(to_char(new.date at time zone 'America/Jamaica', 'Mon FMDD, YYYY'), 'an upcoming date');
  event_title := coalesce(nullif(new.title, ''), 'New church event');

  for member_record in
    select id
    from public.users
    where "placeId" = new."churchId"
      and id is not null
  loop
    perform public.create_notification(
      member_record.id,
      actor_uuid,
      'pastor_event',
      coalesce(nullif(new."sourceLabel", ''), 'From the Pastor''s Desk'),
      event_title || ' is scheduled for ' || event_date ||
        case when nullif(new.time, '') is not null then ' at ' || new.time else '' end,
      new."churchId",
      'events',
      new.id,
      '/events'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists notify_church_members_on_event_trigger on public.events;
create trigger notify_church_members_on_event_trigger
  after insert on public.events
  for each row
  execute function public.notify_church_members_on_event();

drop policy if exists "Members insert prayers" on public.prayer_requests;
drop policy if exists "Members view church prayers" on public.prayer_requests;
drop policy if exists "Prayer Team updates prayers" on public.prayer_requests;
drop policy if exists "Church prayer visibility" on public.prayer_requests;
drop policy if exists "Prayer team updates prayers" on public.prayer_requests;

create policy "Members insert prayers"
  on public.prayer_requests
  for insert
  to authenticated
  with check (
    "userId" = auth.uid()::text
    and "churchId" = public.get_church_id()
  );

create policy "Church prayer visibility"
  on public.prayer_requests
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or "isPrivate" is not true
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Prayer Warrior',
        'Intercessor',
        'Prayer Ministry Leader',
        'Deacon',
        'Elder'
      ])
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
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Prayer Warrior',
        'Intercessor',
        'Prayer Ministry Leader',
        'Deacon',
        'Elder'
      ])
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Prayer Warrior',
        'Intercessor',
        'Prayer Ministry Leader',
        'Deacon',
        'Elder'
      ])
    )
  );

drop policy if exists "Counselors update status" on public.counseling_requests;
drop policy if exists "Private view of counseling" on public.counseling_requests;
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
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Counselor',
        'Care Counseling Coordinator',
        'Deacon',
        'Deaconess',
        'Elder'
      ])
    )
  );

create policy "Care team update counseling"
  on public.counseling_requests
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Counselor',
      'Care Counseling Coordinator',
      'Deacon',
      'Deaconess',
      'Elder'
    ])
  )
  with check (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Counselor',
      'Care Counseling Coordinator',
      'Deacon',
      'Deaconess',
      'Elder'
    ])
  );

drop policy if exists "Admins view audit logs" on public.audit_logs;
drop policy if exists "Role managers view audit logs" on public.audit_logs;
create policy "Role managers view audit logs"
  on public.audit_logs
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Administrator'
    ])
  );

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
  normalized_role text := public.normalize_role_name(role_name);
  next_roles text[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage roles for your church';
  end if;

  if not public.has_any_role(array[
    'Pastor',
    'Senior Pastor',
    'Assistant Pastor',
    'Acting Pastor',
    'Admin',
    'Church Admin',
    'Administrator'
  ]) then
    raise exception 'You do not have permission to assign roles';
  end if;

  if normalized_role in ('pastor', 'senior_pastor') and not public.has_any_role(array[
    'Pastor',
    'Senior Pastor',
    'Church Admin'
  ]) then
    raise exception 'Only church leadership can assign pastor roles';
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
  else
    update public.users
    set roles = (
      select array_agg(distinct role_value)
      from unnest(coalesce(roles, '{}'::text[]) || role_name) as role_value
    )
    where uid = target_uid
    returning roles into next_roles;
  end if;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    church_id,
    case when lower(coalesce(role_action, 'add')) = 'remove' then 'role_removed' else 'role_assigned' end,
    actor_uid,
    jsonb_build_object(
      'targetUid', target_uid,
      'roleChanged', role_name,
      'rolesAfter', next_roles
    )
  );

  return 'ok';
end;
$$;

create or replace function public.notify_staff_on_prayer_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
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
      and exists (
        select 1
        from unnest(coalesce(u.roles, '{}'::text[])) as role_name
        where public.normalize_role_name(role_name) = any(array[
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'admin',
          'church_admin',
          'prayer_warrior',
          'intercessor',
          'prayer_ministry_leader'
        ])
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

drop trigger if exists notify_staff_on_prayer_request_trigger on public.prayer_requests;
create trigger notify_staff_on_prayer_request_trigger
  after insert on public.prayer_requests
  for each row
  execute function public.notify_staff_on_prayer_request();

create or replace function public.notify_staff_on_counseling_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
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
      and exists (
        select 1
        from unnest(coalesce(u.roles, '{}'::text[])) as role_name
        where public.normalize_role_name(role_name) = any(array[
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'admin',
          'church_admin',
          'counselor',
          'care_counseling_coordinator',
          'deacon',
          'deaconess',
          'elder'
        ])
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

drop trigger if exists notify_staff_on_counseling_request_trigger on public.counseling_requests;
create trigger notify_staff_on_counseling_request_trigger
  after insert on public.counseling_requests
  for each row
  execute function public.notify_staff_on_counseling_request();

do $$
declare
  table_name text;
begin
  foreach table_name in array array['events', 'prayer_requests', 'counseling_requests', 'audit_logs']
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
end $$;
