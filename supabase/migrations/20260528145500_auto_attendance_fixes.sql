create extension if not exists pgcrypto;

create table if not exists public.church_locations (
  id uuid not null default gen_random_uuid(),
  "placeId" text primary key,
  "churchId" text not null,
  latitude double precision not null,
  longitude double precision not null,
  "radiusMeters" double precision not null default 150,
  timezone text not null default 'America/Jamaica',
  address text,
  "createdAt" timestamptz not null default now(),
  "updatedAt" timestamptz not null default now()
);

alter table public.church_locations
  add column if not exists id uuid not null default gen_random_uuid();

alter table public.church_locations enable row level security;

drop policy if exists "Church members view location" on public.church_locations;
drop policy if exists "Church staff manage location" on public.church_locations;

create policy "Church members view location"
  on public.church_locations
  for select
  to authenticated
  using (
    "placeId" = public.get_church_id()
    or "churchId" = public.get_church_id()
  );

create policy "Church staff manage location"
  on public.church_locations
  for all
  to authenticated
  using (
    ("placeId" = public.get_church_id() or "churchId" = public.get_church_id())
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Administrator',
      'Church Secretary',
      'Secretary'
    ])
  )
  with check (
    ("placeId" = public.get_church_id() or "churchId" = public.get_church_id())
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Administrator',
      'Church Secretary',
      'Secretary'
    ])
  );

insert into public.church_locations (
  "placeId",
  "churchId",
  latitude,
  longitude,
  "radiusMeters",
  timezone,
  address
)
select
  coalesce(nullif(c."placeId", ''), c.id),
  c.id,
  c.latitude,
  c.longitude,
  150,
  coalesce(nullif(c.timezone, ''), 'America/Jamaica'),
  c.address
from public.churches c
where c.latitude is not null
  and c.longitude is not null
on conflict ("placeId") do update
  set latitude = excluded.latitude,
      longitude = excluded.longitude,
      "churchId" = excluded."churchId",
      timezone = excluded.timezone,
      address = excluded.address,
      "updatedAt" = now();

drop policy if exists "Scanners insert attendance" on public.attendance;
drop policy if exists "Users view own attendance, Admins view all" on public.attendance;
drop policy if exists "Members insert own attendance" on public.attendance;
drop policy if exists "Attendance staff insert attendance" on public.attendance;
drop policy if exists "Church attendance visibility" on public.attendance;

create policy "Members insert own attendance"
  on public.attendance
  for insert
  to authenticated
  with check (
    user_id = auth.uid()::text
    and church_id = public.get_church_id()
  );

create policy "Attendance staff insert attendance"
  on public.attendance
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and public.has_any_role(array[
      'Attendance Scanner',
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Administrator',
      'Usher Lead',
      'Head Usher'
    ])
  );

create policy "Church attendance visibility"
  on public.attendance
  for select
  to authenticated
  using (
    user_id = auth.uid()::text
    or (
      church_id = public.get_church_id()
      and public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Attendance Scanner',
        'Usher Lead',
        'Head Usher'
      ])
    )
  );

do $$
declare
  table_name text;
begin
  foreach table_name in array array['attendance', 'church_locations', 'service_schedules']
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
