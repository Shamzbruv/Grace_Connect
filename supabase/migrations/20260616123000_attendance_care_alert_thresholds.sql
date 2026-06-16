create extension if not exists pgcrypto;

create table if not exists public.church_attendance_alert_settings (
  church_id text primary key,
  absence_threshold_weeks integer not null default 2
    check (absence_threshold_weeks between 1 and 26),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text
);

alter table public.church_attendance_alert_settings
  add column if not exists absence_threshold_weeks integer not null default 2
    check (absence_threshold_weeks between 1 and 26),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by text;

alter table public.church_attendance_alert_settings enable row level security;

drop policy if exists "Church members view attendance alert settings"
  on public.church_attendance_alert_settings;
create policy "Church members view attendance alert settings"
  on public.church_attendance_alert_settings
  for select
  to authenticated
  using (church_id = public.get_church_id());

drop policy if exists "Pastors and admins manage attendance alert settings"
  on public.church_attendance_alert_settings;
create policy "Pastors and admins manage attendance alert settings"
  on public.church_attendance_alert_settings
  for all
  to authenticated
  using (
    church_id = public.get_church_id()
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Admin',
      'Church Admin',
      'Administrator'
    ])
  )
  with check (
    church_id = public.get_church_id()
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

create table if not exists public.priority_follow_ups (
  id uuid primary key default gen_random_uuid(),
  "userId" text not null,
  "userName" text not null default 'Member',
  "userPhotoUrl" text not null default '',
  "churchId" text not null,
  "flaggedAt" timestamptz not null default now(),
  "absenceStreakWeeks" integer not null default 0,
  "lastAttendedDate" timestamptz,
  status text not null default 'open'
    check (status in ('open', 'acknowledged', 'resolved')),
  "resolvedBy" text,
  "resolvedAt" timestamptz,
  notes text[] not null default '{}'::text[],
  "createdAt" timestamptz not null default now(),
  "updatedAt" timestamptz not null default now()
);

alter table public.priority_follow_ups
  add column if not exists "userId" text not null default '',
  add column if not exists "userName" text not null default 'Member',
  add column if not exists "userPhotoUrl" text not null default '',
  add column if not exists "churchId" text not null default '',
  add column if not exists "flaggedAt" timestamptz not null default now(),
  add column if not exists "absenceStreakWeeks" integer not null default 0,
  add column if not exists "lastAttendedDate" timestamptz,
  add column if not exists status text not null default 'open',
  add column if not exists "resolvedBy" text,
  add column if not exists "resolvedAt" timestamptz,
  add column if not exists notes text[] not null default '{}'::text[],
  add column if not exists "createdAt" timestamptz not null default now(),
  add column if not exists "updatedAt" timestamptz not null default now();

create index if not exists priority_follow_ups_church_status_idx
  on public.priority_follow_ups ("churchId", status, "flaggedAt" desc);

create index if not exists priority_follow_ups_user_idx
  on public.priority_follow_ups ("userId", status);

create unique index if not exists priority_follow_ups_one_open_per_member_idx
  on public.priority_follow_ups ("churchId", "userId")
  where status = 'open';

alter table public.priority_follow_ups enable row level security;

drop policy if exists "Church members view open attendance care alerts"
  on public.priority_follow_ups;
create policy "Church members view open attendance care alerts"
  on public.priority_follow_ups
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and status = 'open'
  );

drop policy if exists "Pastors and admins view all attendance care alerts"
  on public.priority_follow_ups;
create policy "Pastors and admins view all attendance care alerts"
  on public.priority_follow_ups
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

drop policy if exists "Pastors and admins manage attendance care alerts"
  on public.priority_follow_ups;
create policy "Pastors and admins manage attendance care alerts"
  on public.priority_follow_ups
  for all
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
      'Administrator'
    ])
  );

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'priority_follow_ups',
    'church_attendance_alert_settings'
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
end $$;
