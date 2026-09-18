-- Run against an isolated database, or in one rollback-only SQL transaction.
-- Requires the attendance arrival acknowledgement migration to be installed.
-- All auth users, churches, memberships, schedules and records below roll back.
begin;
create temporary table attendance_assertions (description text not null);
create or replace function pg_temp.attendance_assert(
  condition boolean, description text
) returns void language plpgsql as $$
begin
  if condition is distinct from true then
    raise exception 'Attendance regression failed: %', description;
  end if;
  insert into attendance_assertions values (description);
end;
$$;

do $test$
declare
  fixture_user uuid := gen_random_uuid();
  fixture_church text := 'attendance_audit_' || gen_random_uuid()::text;
  fixture_service text;
  service_day date := (now() at time zone 'America/Jamaica')::date - 1;
  service_start timestamptz;
  arrived_at timestamptz;
  record_result jsonb;
  second_result jsonb;
  scenario record;
  observed_start timestamptz := now() - interval '11 minutes';
  live_start timestamptz := now() - interval '20 minutes';
  live_end timestamptz := now() + interval '40 minutes';
  close_start timestamptz := now() - interval '40 minutes';
  close_end timestamptz := now() - interval '5 minutes';
  rejected boolean;
  midnight_day date;
begin
  perform pg_temp.attendance_assert(
    not has_table_privilege('authenticated', 'public.attendance', 'INSERT'),
    'members cannot bypass the validated attendance RPC');
  perform pg_temp.attendance_assert(
    not has_function_privilege('anon',
      'public.observe_my_attendance_presence(text,text,timestamptz)', 'EXECUTE'),
    'anonymous callers cannot observe attendance');
  perform pg_temp.attendance_assert(
    has_function_privilege('authenticated',
      'public.observe_my_attendance_presence(text,text,timestamptz)', 'EXECUTE'),
    'authenticated callers can use the opt-in observer');

  insert into auth.users (id, email, aud, role)
  values (fixture_user, fixture_user::text || '@attendance-audit.invalid',
    'authenticated', 'authenticated');
  insert into public.churches (id, name, church_status, timezone)
  values (fixture_church, 'Rollback attendance audit', 'approved', 'America/Jamaica');
  insert into public.church_memberships (
    user_id, church_id, membership_status, reviewed_at
  ) values (fixture_user, fixture_church, 'active', now() - interval '7 days');
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', fixture_user::text, 'role', 'authenticated')::text,
    true);
  service_start := (service_day + time '08:30') at time zone 'America/Jamaica';

  for scenario in
    select * from (values
      ('early', -1800, 'on_time', 30, null::integer),
      ('fractional_early', -30, 'on_time', 1, null::integer),
      ('exact_start', 0, 'on_time', 0, null::integer),
      ('grace_boundary', 600, 'on_time', 0, null::integer),
      ('late', 601, 'late', 0, 10)
    ) as cases(name, seconds_from_start, expected_status, expected_early, expected_late)
  loop
    fixture_service := fixture_church || '_' || scenario.name;
    insert into public.service_schedules (
      "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime"
    ) values (fixture_service, fixture_church, scenario.name,
      extract(isodow from service_day)::integer, '08:30', '09:40');
    arrived_at := service_start + make_interval(secs => scenario.seconds_from_start);
    record_result := public.record_my_attendance(
      fixture_church, fixture_service, arrived_at,
      'manual_geofence', true, 'on_time', null, null, null, scenario.name
    );
    perform pg_temp.attendance_assert(
      (record_result ->> 'present')::boolean
      and record_result ->> 'attendance_id' is not null
      and record_result ->> 'status' = scenario.expected_status
      and (record_result ->> 'minutes_early')::integer = scenario.expected_early
      and (record_result ->> 'minutes_late')::integer is not distinct from scenario.expected_late
      and (record_result ->> 'timestamp')::timestamptz = arrived_at,
      scenario.name || ' receives the persisted arrival acknowledgement');

    second_result := public.record_my_attendance(
      fixture_church, fixture_service, service_start + interval '20 minutes',
      'manual_geofence', true, 'late', 20, null, null, scenario.name
    );
    perform pg_temp.attendance_assert(
      second_result ->> 'attendance_id' = record_result ->> 'attendance_id'
      and (second_result ->> 'inserted')::boolean = false
      and second_result ->> 'status' = record_result ->> 'status'
      and (second_result ->> 'timestamp')::timestamptz = arrived_at
      and (select count(*) from public.attendance
        where service_id = fixture_service) = 1,
      scenario.name || ' retry keeps the original attendance and grade');
  end loop;

  fixture_service := fixture_church || '_early';
  rejected := false;
  begin
    perform public.record_my_attendance(
      fixture_church, fixture_service, service_start - interval '30 minutes 1 second',
      'manual_geofence', true, 'on_time', null, null, null, 'too early');
  exception when sqlstate '22023' then rejected := true;
  end;
  perform pg_temp.attendance_assert(rejected,
    'manual check-in cannot precede the configured opening window');

  rejected := false;
  begin
    perform public.record_my_attendance(
      fixture_church || '_unrelated', fixture_service, service_start,
      'manual_geofence', true, 'on_time', null, null, null, 'unauthorized');
  exception when sqlstate '42501' then rejected := true;
  end;
  perform pg_temp.attendance_assert(rejected,
    'a member cannot check in for another church');

  fixture_service := fixture_church || '_promotion';
  insert into public.service_schedules (
    "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime"
  ) values (fixture_service, fixture_church, 'promotion',
    extract(isodow from service_day)::integer, '08:30', '09:40');
  insert into public.attendance (
    user_id, church_id, service_id, service_date, "timestamp", method, present, status
  ) values (fixture_user::text, fixture_church, fixture_service, service_day,
    service_start + interval '100 minutes', 'auto_absent', false, 'absent');
  insert into public.attendance_finalized_services (
    church_id, service_id, service_date, absent_count
  ) values (fixture_church, fixture_service, service_day, 1);
  record_result := public.record_my_attendance(
    fixture_church, fixture_service, service_start - interval '15 minutes',
    'manual_geofence', true, 'on_time', null, null, null, 'promotion');
  perform pg_temp.attendance_assert(
    (record_result ->> 'present')::boolean
    and (record_result ->> 'minutes_early')::integer = 15
    and (select absent_count = 0 and present_count = 1
      from public.attendance_finalized_services where service_id = fixture_service),
    'a legitimate queued arrival promotes an automatic absence and corrects totals');

  fixture_service := fixture_church || '_remote';
  insert into public.service_schedules (
    "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime"
  ) values (fixture_service, fixture_church, 'remote',
    extract(isodow from service_day)::integer, '08:30', '09:40');
  record_result := public.record_my_attendance(
    fixture_church, fixture_service, service_start - interval '15 minutes',
    'remote', true, 'remote_verified', null, null, 'fixture', 'remote');
  perform pg_temp.attendance_assert(
    record_result ->> 'status' = 'remote_verified'
    and (record_result ->> 'minutes_early')::integer = 0,
    'remote attendance does not receive on-site early credit');

  for scenario in select unnest(array['observer', 'legacy', 'cancelled']) as name loop
    fixture_service := fixture_church || '_' || scenario.name;
    insert into public.service_schedules (
      "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime",
      "checkInOpensMinutesBefore", "minimumDwellMinutes"
    ) values (fixture_service, fixture_church, scenario.name,
      extract(isodow from live_start at time zone 'America/Jamaica')::integer,
      to_char(live_start at time zone 'America/Jamaica', 'HH24:MI:SS'),
      to_char(live_end at time zone 'America/Jamaica', 'HH24:MI:SS'), 30, 10);
  end loop;
  fixture_service := fixture_church || '_observer';
  record_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, observed_start);
  perform pg_temp.attendance_assert(
    record_result ->> 'status' = 'pending'
    and record_result ->> 'attendance_id' is null
    and not exists(select 1 from public.attendance where service_id = fixture_service),
    'one observation never fabricates completed attendance');
  second_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, observed_start);
  perform pg_temp.attendance_assert(second_result ->> 'status' = 'pending',
    'replaying the same observation does not complete dwell');
  record_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, observed_start + interval '10 minutes');
  perform pg_temp.attendance_assert(
    record_result ->> 'status' = 'confirmed'
    and record_result ->> 'attendance_id' is not null
    and (record_result #>> '{attendance,timestamp}')::timestamptz = observed_start
    and (select present from public.attendance where service_id = fixture_service),
    'second real observation atomically confirms using original arrival time');
  second_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, now());
  perform pg_temp.attendance_assert(
    second_result ->> 'attendance_id' = record_result ->> 'attendance_id'
    and (select count(*) from public.attendance where service_id = fixture_service) = 1,
    'confirmed observer retries are idempotent');

  fixture_service := fixture_church || '_legacy';
  perform public.record_my_attendance_presence(
    fixture_church, fixture_service, observed_start);
  record_result := public.record_my_attendance_presence(
    fixture_church, fixture_service, now());
  perform pg_temp.attendance_assert(
    record_result ->> 'status' = 'pending'
    and not exists(select 1 from public.attendance where service_id = fixture_service),
    'legacy manual-screen presence never silently enables auto attendance');

  fixture_service := fixture_church || '_cancelled';
  perform public.observe_my_attendance_presence(
    fixture_church, fixture_service, observed_start);
  perform public.cancel_my_attendance_presence(
    fixture_church, fixture_service, now() - interval '2 minutes');
  record_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, now());
  perform pg_temp.attendance_assert(
    record_result ->> 'status' = 'pending'
    and not exists(select 1 from public.attendance where service_id = fixture_service),
    'a verified exit clears the old dwell before a later entry');

  for scenario in select unnest(array['after_close', 'new_after_close']) as name loop
    fixture_service := fixture_church || '_' || scenario.name;
    insert into public.service_schedules (
      "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime",
      "checkInClosesMinutesAfter", "minimumDwellMinutes"
    ) values (fixture_service, fixture_church, scenario.name,
      extract(isodow from close_start at time zone 'America/Jamaica')::integer,
      to_char(close_start at time zone 'America/Jamaica', 'HH24:MI:SS'),
      to_char(close_end at time zone 'America/Jamaica', 'HH24:MI:SS'), 0, 10);
  end loop;
  fixture_service := fixture_church || '_after_close';
  perform public.observe_my_attendance_presence(
    fixture_church, fixture_service, observed_start);
  record_result := public.observe_my_attendance_presence(
    fixture_church, fixture_service, now());
  perform pg_temp.attendance_assert(record_result ->> 'status' = 'confirmed',
    'a valid existing arrival can finish its dwell after check-in closes');
  rejected := false;
  begin
    perform public.observe_my_attendance_presence(
      fixture_church, fixture_church || '_new_after_close', now());
  exception when sqlstate '22023' then rejected := true;
  end;
  perform pg_temp.attendance_assert(rejected,
    'after-close allowance cannot create a fresh arrival');

  midnight_day := service_day;
  fixture_service := fixture_church || '_midnight';
  insert into public.service_schedules (
    "serviceId", "churchId", name, "dayOfWeek", "startTime", "endTime"
  ) values (fixture_service, fixture_church, 'midnight',
    extract(isodow from midnight_day)::integer, '00:15', '01:00');
  arrived_at := (midnight_day + time '00:15') at time zone 'America/Jamaica'
    - interval '20 minutes';
  record_result := public.record_my_attendance(
    fixture_church, fixture_service, arrived_at,
    'manual_geofence', true, 'on_time', null, null, null, 'midnight');
  perform pg_temp.attendance_assert(
    (record_result ->> 'service_date')::date = midnight_day
    and (record_result ->> 'minutes_early')::integer = 20,
    'before-midnight early check-in belongs to the following service day');

  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  rejected := false;
  begin
    perform public.observe_my_attendance_presence(
      fixture_church, fixture_church || '_observer', now());
  exception when sqlstate '42501' then rejected := true;
  end;
  perform pg_temp.attendance_assert(rejected,
    'observer validates the authenticated user inside its privileged body');
end;
$test$;

select count(*) as assertions_passed, jsonb_agg(description) as assertions
from attendance_assertions;
rollback;
