-- Arrival acknowledgement and early manual check-in, without rewriting history.
-- Keep released clients compatible: early attendance is still status on_time.
alter table public.attendance
  add column if not exists minutes_early integer not null default 0;
alter table public.attendance
  add constraint attendance_minutes_early_nonnegative check (minutes_early >= 0);
comment on column public.attendance.minutes_early is
  'Whole minutes before scheduled start, rounded up; computed by validated RPC.';

-- An early check-in can belong to tomorrow's just-after-midnight service.
CREATE OR REPLACE FUNCTION private.attendance_service_occurrence(p_church_id text, p_service_id text, p_observed_at timestamp with time zone)
 RETURNS TABLE(church_id text, service_date date, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, check_in_opens timestamp with time zone, check_in_closes timestamp with time zone, required_dwell_seconds integer, ready_to_finalize_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with candidate_dates(service_date) as (
    values
      ((p_observed_at at time zone 'America/Jamaica')::date),
      ((p_observed_at at time zone 'America/Jamaica')::date - 1),
      ((p_observed_at at time zone 'America/Jamaica')::date + 1)
  )
  select bounds.*
  from candidate_dates candidate
  cross join lateral private.attendance_service_bounds(
    p_church_id,
    p_service_id,
    candidate.service_date
  ) bounds
  where p_observed_at >= bounds.check_in_opens
    and p_observed_at < bounds.check_in_closes
  order by bounds.scheduled_start desc
  limit 1;
$function$;


CREATE OR REPLACE FUNCTION public.record_my_attendance(p_church_id text, p_service_id text, p_timestamp timestamp with time zone, p_method text, p_present boolean, p_status text, p_minutes_late integer, p_reason_for_absence text, p_engagement_answer text, p_service_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id text := auth.uid()::text;
  attendance_timestamp timestamptz := coalesce(p_timestamp, now());
  occurrence record;
  attendance_id public.attendance.id%type;
  was_inserted boolean := false;
  persisted public.attendance%rowtype;
  computed_status text;
  computed_minutes_late integer;
  computed_minutes_early integer := 0;
begin
  if caller_id is null or caller_id = '' then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null then
    raise exception 'Church and service are required.' using errcode = '22023';
  end if;

  if not private.is_active_attendance_member(auth.uid(), p_church_id) then
    raise exception 'Attendance must be recorded for your active church.'
      using errcode = '42501';
  end if;

  if attendance_timestamp > now() + interval '5 minutes'
      or attendance_timestamp < now() - interval '16 days' then
    raise exception 'The attendance time is outside the accepted delivery window.'
      using errcode = '22023';
  end if;

  if coalesce(p_present, false) is not true then
    raise exception 'Members may only record their own presence.'
      using errcode = '42501';
  end if;

  if coalesce(p_method, '') not in (
    'auto_geofence', 'manual_geofence', 'manual', 'qr', 'remote'
  ) then
    raise exception 'Unsupported attendance method.' using errcode = '22023';
  end if;

  if coalesce(p_status, '') not in (
    'on_time', 'late', 'remote_verified'
  ) then
    raise exception 'Unsupported attendance status.' using errcode = '22023';
  end if;

  if (p_method = 'remote' and p_status <> 'remote_verified')
      or (p_method <> 'remote' and p_status = 'remote_verified') then
    raise exception 'Attendance method and status do not match.'
      using errcode = '22023';
  end if;

  if p_status = 'late' and coalesce(p_minutes_late, 0) < 0 then
    raise exception 'Minutes late cannot be negative.' using errcode = '22023';
  end if;

  select bounds.*
    into occurrence
  from private.attendance_service_occurrence(
    p_church_id,
    p_service_id,
    attendance_timestamp
  ) bounds;
  if not found then
    raise exception 'Attendance was recorded outside the service check-in window.'
      using errcode = '22023';
  end if;

  -- Keep the existing ten-minute grace; grade the actual arrival on the server.
  -- Early attendance remains on_time for released clients and reports.
  if p_method = 'remote' then
    computed_status := 'remote_verified';
    computed_minutes_late := null;
  elsif attendance_timestamp > occurrence.scheduled_start + interval '10 minutes' then
    computed_status := 'late';
    computed_minutes_late := floor(extract(epoch from (
      attendance_timestamp - occurrence.scheduled_start
    )) / 60)::integer;
  else
    computed_status := 'on_time';
    computed_minutes_late := null;
    computed_minutes_early := greatest(0, ceil(extract(epoch from (
      occurrence.scheduled_start - attendance_timestamp
    )) / 60)::integer);
  end if;

  if p_method = 'auto_geofence' and not exists (
    select 1
    from public.attendance_presence_claims claim
    where claim.church_id = occurrence.church_id
      and claim.service_id = p_service_id
      and claim.service_date = occurrence.service_date
      and claim.user_id = caller_id
      and now() >= claim.first_inside_at
        + make_interval(secs => claim.required_dwell_seconds)
  ) then
    raise exception 'Automatic attendance requires a completed server presence claim.'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', occurrence.church_id, ':', p_service_id, ':',
      occurrence.service_date
    ),
    0
  ));

  insert into public.attendance as existing (
    user_id,
    church_id,
    service_id,
    service_date,
    "timestamp",
    method,
    present,
    status,
    minutes_late,
    minutes_early,
    reason_for_absence,
    engagement_answer,
    service_name
  ) values (
    caller_id,
    occurrence.church_id,
    p_service_id,
    occurrence.service_date,
    attendance_timestamp,
    p_method,
    true,
    computed_status,
    computed_minutes_late,
    computed_minutes_early,
    p_reason_for_absence,
    p_engagement_answer,
    p_service_name
  )
  on conflict (church_id, user_id, service_id, service_date)
  do update set
    "timestamp" = excluded."timestamp",
    method = excluded.method,
    present = true,
    status = excluded.status,
    minutes_late = excluded.minutes_late,
    minutes_early = excluded.minutes_early,
    reason_for_absence = excluded.reason_for_absence,
    engagement_answer = excluded.engagement_answer,
    service_name = coalesce(excluded.service_name, existing.service_name)
  where existing.present = false
    and existing.method = 'auto_absent'
  returning id into attendance_id;

  was_inserted := attendance_id is not null;
  if attendance_id is null then
    select attendance.id
      into attendance_id
    from public.attendance attendance
    where attendance.church_id = occurrence.church_id
      and attendance.user_id = caller_id
      and attendance.service_id = p_service_id
      and attendance.service_date = occurrence.service_date
    order by attendance.present desc, attendance."timestamp" asc
    limit 1;
  end if;

  -- A bounded offline retry may legitimately promote an auto-absence after
  -- closeout. Recompute the marker and existing report body in this same lock.
  with attendance_totals as (
    select
      count(*) filter (
        where attendance.present = true
          and coalesce(attendance.method, '') <> 'remote'
          and coalesce(attendance.status, '') not in ('remote_verified', 'late')
      )::integer as present_count,
      count(*) filter (
        where attendance.present = true
          and coalesce(attendance.method, '') <> 'remote'
          and attendance.status = 'late'
      )::integer as late_count,
      count(*) filter (
        where attendance.present = true
          and (
            attendance.method = 'remote'
            or attendance.status = 'remote_verified'
          )
      )::integer as remote_count,
      count(*) filter (
        where attendance.present = false
          or attendance.status = 'absent'
      )::integer as absent_count
    from public.attendance attendance
    where attendance.church_id = occurrence.church_id
      and attendance.service_id = p_service_id
      and attendance.service_date = occurrence.service_date
  )
  update public.attendance_finalized_services finalized
  set present_count = totals.present_count,
      late_count = totals.late_count,
      remote_count = totals.remote_count,
      absent_count = totals.absent_count,
      finalized_at = now()
  from attendance_totals totals
  where finalized.church_id = occurrence.church_id
    and finalized.service_id = p_service_id
    and finalized.service_date = occurrence.service_date;

  update public.notifications notification
  set body = concat(
    finalized.present_count, ' present • ',
    finalized.late_count, ' late • ',
    finalized.remote_count, ' remote • ',
    finalized.absent_count, ' absent for ',
    finalized.service_date, '.'
  )
  from public.attendance_finalized_services finalized
  where finalized.church_id = occurrence.church_id
    and finalized.service_id = p_service_id
    and finalized.service_date = occurrence.service_date
    and notification.entity_table = 'attendance_finalized_services'
    and notification.entity_id = concat(
      finalized.church_id, ':', finalized.service_id, ':',
      finalized.service_date
    );

  select attendance.* into persisted
  from public.attendance attendance
  where attendance.id = attendance_id;

  return jsonb_build_object(
    'id', attendance_id::text,
    'attendance_id', attendance_id::text,
    'present', persisted.present,
    'status', persisted.status,
    'minutes_late', persisted.minutes_late,
    'minutes_early', persisted.minutes_early,
    'timestamp', persisted."timestamp",
    'inserted', was_inserted,
    'church_id', occurrence.church_id,
    'service_date', occurrence.service_date
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.record_my_attendance_presence(p_church_id text, p_service_id text, p_observed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  caller_id text := auth.uid()::text;
  observed_at timestamptz := coalesce(p_observed_at, now());
  occurrence record;
  claim_status text;
  attendance_row public.attendance%rowtype;
begin
  if caller_id is null or caller_id = '' then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null then
    raise exception 'Church and service are required.' using errcode = '22023';
  end if;

  if observed_at > now() + interval '5 minutes' then
    raise exception 'The presence time cannot be in the future.'
      using errcode = '22023';
  end if;

  -- A claim only protects a countdown that the server heard near real time.
  -- Older offline evidence is still accepted by record_my_attendance once the
  -- dwell completes, where it atomically promotes an auto_absent placeholder;
  -- it cannot be replayed here to keep closeout pending indefinitely.
  if observed_at < now() - interval '75 minutes' then
    raise exception 'The pending presence observation is too old.'
      using errcode = '22023';
  end if;

  if not private.is_active_attendance_member(auth.uid(), p_church_id) then
    raise exception 'Attendance presence must belong to your active church.'
      using errcode = '42501';
  end if;

  select bounds.*
    into occurrence
  from private.attendance_service_occurrence(
    p_church_id,
    p_service_id,
    observed_at
  ) bounds;

  if not found then
    -- Someone who entered before closing may finish the dwell afterwards.
    -- A new arrival cannot create a claim after the check-in window.
    select bounds.* into occurrence
    from public.attendance_presence_claims claim
    cross join lateral private.attendance_service_bounds(
      claim.church_id, claim.service_id, claim.service_date
    ) bounds
    where claim.user_id = caller_id
      and claim.service_id = p_service_id
      and (claim.church_id = p_church_id or exists (
        select 1 from public.churches church
        where p_church_id in (church.id::text, church."placeId"::text)
          and claim.church_id in (church.id::text, church."placeId"::text)
      ))
      and claim.first_inside_at >= bounds.check_in_opens
      and claim.first_inside_at < bounds.check_in_closes
      and observed_at >= claim.first_inside_at
      and observed_at <= bounds.ready_to_finalize_at
    order by bounds.scheduled_start desc
    limit 1;
  end if;

  if not found then
    raise exception 'Presence was observed outside the service check-in window.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', occurrence.church_id, ':', p_service_id, ':',
      occurrence.service_date
    ),
    0
  ));

  insert into public.attendance_presence_claims as existing (
    church_id,
    service_id,
    service_date,
    user_id,
    first_inside_at,
    last_inside_at,
    required_dwell_seconds,
    expires_at,
    status,
    updated_at
  ) values (
    occurrence.church_id,
    p_service_id,
    occurrence.service_date,
    caller_id,
    observed_at,
    observed_at,
    occurrence.required_dwell_seconds,
    occurrence.ready_to_finalize_at,
    'pending',
    now()
  )
  on conflict (church_id, service_id, service_date, user_id)
  do update set
    first_inside_at = least(existing.first_inside_at, excluded.first_inside_at),
    last_inside_at = greatest(existing.last_inside_at, excluded.last_inside_at),
    required_dwell_seconds = excluded.required_dwell_seconds,
    expires_at = greatest(existing.expires_at, excluded.expires_at),
    status = case
      when existing.status = 'confirmed' then 'confirmed'
      else 'pending'
    end,
    confirmed_at = case
      when existing.status = 'confirmed' then existing.confirmed_at
      else null
    end,
    updated_at = now();

  -- If presence was already committed before this claim retried, make the
  -- claim terminal immediately. A pending claim never creates or alters an
  -- attendance row; it only makes scheduled closeout wait for the real,
  -- idempotent record_my_attendance write.
  if exists (
    select 1
    from public.attendance attendance
    where attendance.church_id = occurrence.church_id
      and attendance.service_id = p_service_id
      and attendance.user_id = caller_id
      and attendance.service_date = occurrence.service_date
      and attendance.present = true
  ) then
    update public.attendance_presence_claims claim
    set status = 'confirmed', confirmed_at = now(), updated_at = now()
    where claim.church_id = occurrence.church_id
      and claim.service_id = p_service_id
      and claim.service_date = occurrence.service_date
      and claim.user_id = caller_id;
  end if;

  select claim.status
    into claim_status
  from public.attendance_presence_claims claim
  where claim.church_id = occurrence.church_id
    and claim.service_id = p_service_id
    and claim.service_date = occurrence.service_date
    and claim.user_id = caller_id;

  select attendance.* into attendance_row
  from public.attendance attendance
  where attendance.church_id = occurrence.church_id
    and attendance.service_id = p_service_id
    and attendance.user_id = caller_id
    and attendance.service_date = occurrence.service_date
    and attendance.present = true;

  return jsonb_build_object(
    'attendance_id', attendance_row.id::text,
    'attendance', case when attendance_row.id is not null then
      jsonb_build_object(
        'attendance_id', attendance_row.id::text,
        'present', attendance_row.present,
        'status', attendance_row.status,
        'timestamp', attendance_row."timestamp",
        'minutes_early', attendance_row.minutes_early,
        'minutes_late', attendance_row.minutes_late
      ) else null end,
    'church_id', occurrence.church_id,
    'service_date', occurrence.service_date,
    'status', claim_status,
    'expires_at', occurrence.ready_to_finalize_at
  );
end;
$function$;


-- Only new clients that explicitly enabled automatic attendance call this
-- endpoint. Legacy clients use record_my_attendance_presence to start a claim,
-- including while displaying manual check-in; that endpoint stays pending-only.
create or replace function public.observe_my_attendance_presence(
  p_church_id text,
  p_service_id text,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
  claim_row public.attendance_presence_claims%rowtype;
  attendance_result jsonb;
begin
  -- Validate identity, active membership, freshness, exact service window and
  -- any after-close claim. Its service lock remains held in this transaction.
  result := public.record_my_attendance_presence(
    p_church_id, p_service_id, p_observed_at
  );

  select claim.* into claim_row
  from public.attendance_presence_claims claim
  where claim.church_id = result ->> 'church_id'
    and claim.service_id = p_service_id
    and claim.service_date = (result ->> 'service_date')::date
    and claim.user_id = auth.uid()::text;

  -- A single observation never confirms attendance. A later inside observation
  -- must cover the complete dwell, and server time must agree.
  if claim_row.status <> 'confirmed'
      and claim_row.last_inside_at >= claim_row.first_inside_at
        + make_interval(secs => claim_row.required_dwell_seconds)
      and now() >= claim_row.first_inside_at
        + make_interval(secs => claim_row.required_dwell_seconds) then
    attendance_result := public.record_my_attendance(
      claim_row.church_id, p_service_id, claim_row.first_inside_at,
      'auto_geofence', true, 'on_time', null, null, null,
      (select schedule.name from public.service_schedules schedule
       where schedule."churchId" = claim_row.church_id
         and schedule."serviceId" = p_service_id limit 1)
    );
    result := result || jsonb_build_object(
      'status', case when (attendance_result ->> 'present')::boolean
        then 'confirmed' else result ->> 'status' end,
      'attendance_id', attendance_result ->> 'attendance_id',
      'attendance', attendance_result
    );
  end if;
  return result;
end;
$$;

revoke all on function public.observe_my_attendance_presence(
  text, text, timestamptz
) from public, anon, service_role;
grant execute on function public.observe_my_attendance_presence(
  text, text, timestamptz
) to authenticated;


notify pgrst, 'reload schema';
