-- Server-side attendance closeout.
-- This marks members absent after service windows close and notifies leaders
-- when Sunday School attendance is ready for review.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

create table if not exists public.attendance_finalized_services (
  church_id text not null,
  service_id text not null,
  service_date date not null,
  service_name text,
  present_count integer not null default 0,
  late_count integer not null default 0,
  remote_count integer not null default 0,
  absent_count integer not null default 0,
  finalized_at timestamptz not null default now(),
  report_sent_at timestamptz,
  primary key (church_id, service_id, service_date)
);

create index if not exists attendance_finalized_services_church_date_idx
  on public.attendance_finalized_services (church_id, service_date desc);

alter table public.attendance_finalized_services enable row level security;

drop policy if exists "Attendance leaders view finalized services"
  on public.attendance_finalized_services;
create policy "Attendance leaders view finalized services"
  on public.attendance_finalized_services
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Church Admin',
        'Administrator',
        'Secretary',
        'Church Secretary',
        'Sunday School Lead',
        'Sunday School Leader',
        'Sunday School Superintendent',
        'Sunday School Teacher',
        'Head Usher'
      ])
      or public.has_app_privilege('viewAttendanceInsights')
      or public.has_app_privilege('manualCheckIn')
      or public.has_app_privilege('manageSchedule')
      or public.has_app_privilege('manageSundaySchool')
    )
  );

grant select on public.attendance_finalized_services to authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'service-attendance-finalizer') then
    perform cron.unschedule('service-attendance-finalizer');
  end if;
end $$;

select cron.schedule(
  'service-attendance-finalizer',
  '*/15 * * * *',
  $$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/finalize-service-attendance',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret' limit 1),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $$
);
