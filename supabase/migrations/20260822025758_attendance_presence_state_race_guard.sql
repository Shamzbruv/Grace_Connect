-- Make automatic attendance a monotonic, race-safe state machine.
--
-- A verified on-site countdown is persisted as a pending presence claim.
-- Scheduled closeout cannot finalize that service while a valid claim is
-- pending, and no automatic absence writer can downgrade confirmed presence.

create extension if not exists pgcrypto;
create schema if not exists private;

create table if not exists public.attendance_presence_claims (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  service_id text not null,
  service_date date not null,
  user_id text not null,
  first_inside_at timestamptz not null,
  last_inside_at timestamptz not null,
  required_dwell_seconds integer not null,
  expires_at timestamptz not null,
  status text not null default 'pending',
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_presence_claims_member_service_day_key
    unique (church_id, service_id, service_date, user_id),
  constraint attendance_presence_claims_dwell_check
    check (required_dwell_seconds between 60 and 3600),
  constraint attendance_presence_claims_status_check
    check (status in ('pending', 'confirmed', 'expired')),
  constraint attendance_presence_claims_confirmation_check
    check ((status = 'confirmed') = (confirmed_at is not null))
);

create index if not exists attendance_pending_presence_service_idx
  on public.attendance_presence_claims (
    church_id,
    service_id,
    service_date,
    expires_at
  )
  where status = 'pending';

alter table public.attendance_presence_claims enable row level security;

-- Claims are an implementation detail of the authenticated RPC below. They
-- are deliberately not exposed for direct client writes or reads.
revoke all on table public.attendance_presence_claims
  from public, anon, authenticated;
grant select, insert, update, delete on table public.attendance_presence_claims
  to service_role;

-- Attendance belongs to the recurring service occurrence, which is not
-- always the same calendar date as the arrival timestamp (for example, a
-- Friday 11 PM service can check somebody in after midnight Saturday).
alter table public.attendance
  add column if not exists service_date date;

update public.attendance attendance
set service_date =
  (coalesce(attendance."timestamp", now()) at time zone 'America/Jamaica')::date
where attendance.service_date is null;

alter table public.attendance
  alter column service_date set not null;

-- Validated RPCs take the occurrence advisory lock and derive auth.uid().
-- A direct grant would let a modified client bypass both guarantees even if
-- an RLS policy still says the row belongs to the caller.
revoke insert, update, delete on table public.attendance
  from anon, authenticated;

create or replace function private.is_active_attendance_member(
  p_user_id uuid,
  p_church_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.church_memberships membership
    join public.churches church
      on church.id::text = membership.church_id
      or church."placeId"::text = membership.church_id
    where membership.user_id = p_user_id
      and membership.membership_status = 'active'
      and p_church_id in (
        membership.church_id,
        church.id::text,
        church."placeId"::text
      )
      and church.church_status = 'approved'
  );
$$;

revoke all on function private.is_active_attendance_member(uuid, text)
  from public, anon, authenticated, service_role;

-- This is the single SQL definition of a service occurrence. The Edge helper
-- implements the same exact HH:MM[:SS] parser, overnight rule, and clamps.
create or replace function private.attendance_service_bounds(
  p_church_id text,
  p_service_id text,
  p_service_date date
)
returns table (
  church_id text,
  service_date date,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  check_in_opens timestamptz,
  check_in_closes timestamptz,
  required_dwell_seconds integer,
  ready_to_finalize_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  schedule_row public.service_schedules%rowtype;
  local_start timestamp;
  local_end timestamp;
  local_opens timestamp;
  local_closes timestamp;
  dwell_seconds integer;
begin
  select schedule.*
    into schedule_row
  from public.service_schedules schedule
  where schedule."serviceId" = p_service_id
    and coalesce(schedule."attendanceEnabled", true) = true
    and schedule."dayOfWeek" = extract(isodow from p_service_date)::integer
    and (
      schedule."churchId" = p_church_id
      or exists (
        select 1
        from public.churches church
        where p_church_id in (church.id::text, church."placeId"::text)
          and schedule."churchId" in (
            church.id::text,
            church."placeId"::text
          )
      )
    )
  order by (schedule."churchId" = p_church_id) desc
  limit 1;

  if not found then
    return;
  end if;

  if trim(schedule_row."startTime") !~
        '^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$'
      or trim(schedule_row."endTime") !~
        '^([01]?[0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then
    return;
  end if;

  local_start := p_service_date + trim(schedule_row."startTime")::time;
  local_end := p_service_date + trim(schedule_row."endTime")::time;
  if local_end <= local_start then
    local_end := local_end + interval '1 day';
  end if;

  local_opens := local_start - make_interval(
    mins => greatest(
      0,
      least(240, coalesce(schedule_row."checkInOpensMinutesBefore", 30))
    )
  );
  local_closes := local_end + make_interval(
    mins => greatest(
      0,
      least(240, coalesce(schedule_row."checkInClosesMinutesAfter", 30))
    )
  );
  dwell_seconds := greatest(
    1,
    least(60, coalesce(schedule_row."minimumDwellMinutes", 10))
  ) * 60;

  return query select
    schedule_row."churchId",
    p_service_date,
    local_start at time zone 'America/Jamaica',
    local_end at time zone 'America/Jamaica',
    local_opens at time zone 'America/Jamaica',
    local_closes at time zone 'America/Jamaica',
    dwell_seconds,
    (
      local_closes
      + make_interval(secs => dwell_seconds)
      + interval '15 minutes'
    ) at time zone 'America/Jamaica';
end;
$$;

revoke all on function private.attendance_service_bounds(text, text, date)
  from public, anon, authenticated, service_role;

create or replace function private.attendance_service_occurrence(
  p_church_id text,
  p_service_id text,
  p_observed_at timestamptz
)
returns table (
  church_id text,
  service_date date,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  check_in_opens timestamptz,
  check_in_closes timestamptz,
  required_dwell_seconds integer,
  ready_to_finalize_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with candidate_dates(service_date) as (
    values
      ((p_observed_at at time zone 'America/Jamaica')::date),
      ((p_observed_at at time zone 'America/Jamaica')::date - 1)
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
$$;

revoke all on function private.attendance_service_occurrence(
  text, text, timestamptz
) from public, anon, authenticated, service_role;

-- Correct historical overnight rows before making occurrence identity
-- unique. The prior calendar-date key allowed a Friday service to have one
-- row before midnight and another after midnight Saturday; retain presence
-- (then earliest evidence) if such legacy duplicates collapse together.
with resolved_occurrences as (
  select
    attendance.ctid as attendance_ctid,
    occurrence.church_id,
    occurrence.service_date
  from public.attendance attendance
  cross join lateral (
    select bounds.*
    from (
      values
        ((attendance."timestamp" at time zone 'America/Jamaica')::date),
        ((attendance."timestamp" at time zone 'America/Jamaica')::date - 1)
    ) candidate(service_date)
    cross join lateral private.attendance_service_bounds(
      attendance.church_id,
      attendance.service_id,
      candidate.service_date
    ) bounds
    where attendance."timestamp" >= bounds.check_in_opens
      and attendance."timestamp" <= bounds.check_in_closes
    order by bounds.scheduled_start desc
    limit 1
  ) occurrence
)
update public.attendance attendance
set church_id = resolved.church_id,
    service_date = resolved.service_date
from resolved_occurrences resolved
where attendance.ctid = resolved.attendance_ctid;

with ranked_occurrences as (
  select
    attendance.ctid,
    row_number() over (
      partition by
        attendance.church_id,
        attendance.user_id,
        attendance.service_id,
        attendance.service_date
      order by
        attendance.present desc,
        attendance."timestamp" asc,
        attendance.id asc
    ) as occurrence_row
  from public.attendance attendance
)
delete from public.attendance attendance
using ranked_occurrences duplicate
where attendance.ctid = duplicate.ctid
  and duplicate.occurrence_row > 1;

create unique index if not exists
  attendance_one_record_per_member_service_occurrence_idx
on public.attendance (church_id, user_id, service_id, service_date);

drop index if exists public.attendance_one_record_per_member_service_day_idx;

create or replace function public.record_my_attendance_presence(
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
  caller_id text := auth.uid()::text;
  observed_at timestamptz := coalesce(p_observed_at, now());
  occurrence record;
  claim_status text;
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

  return jsonb_build_object(
    'church_id', occurrence.church_id,
    'service_date', occurrence.service_date,
    'status', claim_status,
    'expires_at', occurrence.ready_to_finalize_at
  );
end;
$$;

revoke all on function public.record_my_attendance_presence(
  text, text, timestamptz
) from public, anon, service_role;
grant execute on function public.record_my_attendance_presence(
  text, text, timestamptz
) to authenticated;

create or replace function public.cancel_my_attendance_presence(
  p_church_id text,
  p_service_id text,
  p_observed_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id text := auth.uid()::text;
  attendance_date date :=
    (coalesce(p_observed_at, now()) at time zone 'America/Jamaica')::date;
  target_church_id text;
  target_service_date date;
  removed boolean := false;
begin
  if caller_id is null or caller_id = '' then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null then
    raise exception 'Church and service are required.' using errcode = '22023';
  end if;

  select claim.church_id, claim.service_date
    into target_church_id, target_service_date
  from public.attendance_presence_claims claim
  where claim.service_id = p_service_id
    and claim.service_date between attendance_date - 1 and attendance_date
    and claim.user_id = caller_id
    and claim.status = 'pending'
    and claim.expires_at > now()
    and (
      claim.church_id = p_church_id
      or exists (
        select 1
        from public.churches church
        where p_church_id in (church.id::text, church."placeId"::text)
          and claim.church_id in (church.id::text, church."placeId"::text)
      )
    )
  order by claim.service_date desc
  limit 1;

  if not found then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', target_church_id, ':', p_service_id, ':',
      target_service_date
    ),
    0
  ));

  delete from public.attendance_presence_claims claim
  where claim.church_id = target_church_id
    and claim.service_id = p_service_id
    and claim.service_date = target_service_date
    and claim.user_id = caller_id
    and claim.status = 'pending'
    and claim.expires_at > now()
  returning true into removed;

  return coalesce(removed, false);
end;
$$;

revoke all on function public.cancel_my_attendance_presence(
  text, text, timestamptz
) from public, anon, service_role;
grant execute on function public.cancel_my_attendance_presence(
  text, text, timestamptz
) to authenticated;

-- Replace the legacy presence writer so a stale profile, arbitrary timestamp,
-- or direct-table fallback cannot manufacture attendance or race closeout.
create or replace function public.record_my_attendance(
  p_church_id text,
  p_service_id text,
  p_timestamp timestamptz,
  p_method text,
  p_present boolean,
  p_status text,
  p_minutes_late integer,
  p_reason_for_absence text,
  p_engagement_answer text,
  p_service_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id text := auth.uid()::text;
  attendance_timestamp timestamptz := coalesce(p_timestamp, now());
  occurrence record;
  attendance_id public.attendance.id%type;
  was_inserted boolean := false;
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
    p_status,
    p_minutes_late,
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

  return jsonb_build_object(
    'id', attendance_id::text,
    'inserted', was_inserted,
    'church_id', occurrence.church_id,
    'service_date', occurrence.service_date
  );
end;
$$;

revoke all on function public.record_my_attendance(
  text, text, timestamptz, text, boolean, text, integer, text, text, text
) from public, anon, service_role;
grant execute on function public.record_my_attendance(
  text, text, timestamptz, text, boolean, text, integer, text, text, text
) to authenticated;

-- Confirm the pending state no matter which legitimate attendance writer won
-- (automatic, manual, remote, QR, or an offline retry).
create or replace function private.confirm_attendance_presence_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.present = true and coalesce(new.status, '') <> 'absent' then
    update public.attendance_presence_claims claim
    set
      status = 'confirmed',
      confirmed_at = coalesce(claim.confirmed_at, now()),
      last_inside_at = greatest(claim.last_inside_at, new."timestamp"),
      updated_at = now()
    where claim.church_id = new.church_id
      and claim.service_id = new.service_id
      and claim.user_id = new.user_id
      and claim.service_date = new.service_date;
  end if;
  return new;
end;
$$;

revoke all on function private.confirm_attendance_presence_claim()
  from public, anon, authenticated, service_role;

drop trigger if exists attendance_confirm_presence_claim
  on public.attendance;
create trigger attendance_confirm_presence_claim
after insert or update of present, status on public.attendance
for each row execute function private.confirm_attendance_presence_claim();

-- Defense in depth: an automatic closeout can never downgrade a row that has
-- already reached confirmed presence, even if a future writer changes its
-- conflict strategy.
create or replace function private.guard_confirmed_attendance_from_absence()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.present = true
      and coalesce(old.status, '') <> 'absent'
      and (
        new.method = 'auto_absent'
        or new.present = false
        or new.status = 'absent'
      ) then
    raise exception 'Confirmed attendance cannot be overwritten by closeout.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.guard_confirmed_attendance_from_absence()
  from public, anon, authenticated, service_role;

drop trigger if exists attendance_guard_confirmed_presence
  on public.attendance;
create trigger attendance_guard_confirmed_presence
before update on public.attendance
for each row execute function private.guard_confirmed_attendance_from_absence();

create or replace function public.insert_absent_attendance_rows(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data record;
  attendance_date date;
  row_inserted integer := 0;
  inserted_count integer := 0;
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'Service role required.' using errcode = '42501';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return 0;
  end if;

  -- A deterministic order plus the shared service/day lock avoids deadlocks
  -- across overlapping cron runs and member check-in retries.
  for row_data in
    select rows.*
    from jsonb_to_recordset(p_rows) as rows(
      user_id text,
      church_id text,
      service_id text,
      "timestamp" timestamptz,
      service_name text
    )
    where nullif(trim(rows.user_id), '') is not null
      and nullif(trim(rows.church_id), '') is not null
      and nullif(trim(rows.service_id), '') is not null
      and rows."timestamp" is not null
    order by rows.church_id, rows.service_id, rows."timestamp", rows.user_id
  loop
    attendance_date :=
      (row_data."timestamp" at time zone 'America/Jamaica')::date;

    perform pg_advisory_xact_lock(hashtextextended(
      concat(
        'grace-attendance:', row_data.church_id, ':', row_data.service_id,
        ':', attendance_date
      ),
      0
    ));

    update public.attendance_presence_claims claim
    set status = 'expired', updated_at = now()
    where claim.church_id = row_data.church_id
      and claim.service_id = row_data.service_id
      and claim.service_date = attendance_date
      and claim.status = 'pending'
      and claim.expires_at <= now();

    if exists (
      select 1
      from public.attendance_presence_claims claim
      where claim.church_id = row_data.church_id
        and claim.service_id = row_data.service_id
        and claim.service_date = attendance_date
        and claim.user_id = row_data.user_id
        and claim.status = 'pending'
        and claim.expires_at > now()
    ) then
      continue;
    end if;

    insert into public.attendance (
      user_id,
      church_id,
      service_id,
      service_date,
      "timestamp",
      method,
      present,
      status,
      service_name
    ) values (
      row_data.user_id,
      row_data.church_id,
      row_data.service_id,
      attendance_date,
      row_data."timestamp",
      'auto_absent',
      false,
      'absent',
      row_data.service_name
    )
    on conflict do nothing;

    get diagnostics row_inserted = row_count;
    inserted_count := inserted_count + row_inserted;
  end loop;

  return inserted_count;
end;
$$;

revoke all on function public.insert_absent_attendance_rows(jsonb)
  from public, anon, authenticated;
grant execute on function public.insert_absent_attendance_rows(jsonb)
  to service_role;

create or replace function public.finalize_attendance_service(
  p_church_id text,
  p_service_id text,
  p_service_date date,
  p_service_name text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  marker_inserted boolean := false;
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'Service role required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null
      or p_service_date is null then
    raise exception 'Church, service, and service date are required.'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', p_church_id, ':', p_service_id, ':',
      p_service_date
    ),
    0
  ));

  update public.attendance_presence_claims claim
  set status = 'expired', updated_at = now()
  where claim.church_id = p_church_id
    and claim.service_id = p_service_id
    and claim.service_date = p_service_date
    and claim.status = 'pending'
    and claim.expires_at <= now();

  -- Returning false leaves the Edge finalizer retryable and prevents both the
  -- durable marker and leader report from claiming a still-running countdown.
  if exists (
    select 1
    from public.attendance_presence_claims claim
    where claim.church_id = p_church_id
      and claim.service_id = p_service_id
      and claim.service_date = p_service_date
      and claim.status = 'pending'
      and claim.expires_at > now()
  ) then
    return false;
  end if;

  with attendance_totals as (
    select
      count(*) filter (
        where attendance.present = true
          and coalesce(attendance.method, '') <> 'remote'
          and coalesce(attendance.status, '') <> 'remote_verified'
          and coalesce(attendance.status, '') <> 'late'
      )::integer as present_count,
      count(*) filter (
        where attendance.present = true
          and coalesce(attendance.method, '') <> 'remote'
          and coalesce(attendance.status, '') <> 'remote_verified'
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
    where attendance.church_id = p_church_id
      and attendance.service_id = p_service_id
      and attendance.service_date = p_service_date
  )
  insert into public.attendance_finalized_services (
    church_id,
    service_id,
    service_date,
    service_name,
    present_count,
    late_count,
    remote_count,
    absent_count,
    finalized_at
  )
  select
    p_church_id,
    p_service_id,
    p_service_date,
    nullif(trim(coalesce(p_service_name, '')), ''),
    totals.present_count,
    totals.late_count,
    totals.remote_count,
    totals.absent_count,
    now()
  from attendance_totals totals
  on conflict (church_id, service_id, service_date) do nothing
  returning true into marker_inserted;

  return coalesce(marker_inserted, false);
end;
$$;

revoke all on function public.finalize_attendance_service(
  text, text, date, text
) from public, anon, authenticated;
grant execute on function public.finalize_attendance_service(
  text, text, date, text
) to service_role;

-- One transaction owns the entire closeout state transition: wait for claims,
-- derive the canonical active-membership population, insert every absence,
-- count the occurrence, and create the final marker. This eliminates the old
-- gap where a claim could expire between a separate absence RPC and marker RPC.
create or replace function public.finalize_attendance_service_v2(
  p_church_id text,
  p_service_id text,
  p_service_date date,
  p_service_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  bounds record;
  inserted_absences integer := 0;
  marker_inserted boolean := false;
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'Service role required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null
      or p_service_date is null then
    raise exception 'Church, service, and service date are required.'
      using errcode = '22023';
  end if;

  select occurrence.*
    into bounds
  from private.attendance_service_bounds(
    p_church_id,
    p_service_id,
    p_service_date
  ) occurrence;
  if not found then
    raise exception 'The service occurrence is not configured.'
      using errcode = '22023';
  end if;

  if now() <= bounds.ready_to_finalize_at then
    return jsonb_build_object(
      'finalized', false,
      'reason', 'not_ready',
      'ready_at', bounds.ready_to_finalize_at,
      'absences_created', 0
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', bounds.church_id, ':', p_service_id, ':',
      p_service_date
    ),
    0
  ));

  update public.attendance_presence_claims claim
  set status = 'expired', confirmed_at = null, updated_at = now()
  where claim.church_id = bounds.church_id
    and claim.service_id = p_service_id
    and claim.service_date = p_service_date
    and claim.status = 'pending'
    and claim.expires_at <= now();

  if exists (
    select 1
    from public.attendance_presence_claims claim
    where claim.church_id = bounds.church_id
      and claim.service_id = p_service_id
      and claim.service_date = p_service_date
      and claim.status = 'pending'
      and claim.expires_at > now()
  ) then
    return jsonb_build_object(
      'finalized', false,
      'reason', 'presence_pending',
      'absences_created', 0
    );
  end if;

  insert into public.attendance (
    user_id,
    church_id,
    service_id,
    service_date,
    "timestamp",
    method,
    present,
    status,
    service_name
  )
  select
    eligible.user_id,
    bounds.church_id,
    p_service_id,
    p_service_date,
    bounds.check_in_closes,
    'auto_absent',
    false,
    'absent',
    nullif(trim(coalesce(p_service_name, '')), '')
  from (
    select distinct membership.user_id::text as user_id
    from public.church_memberships membership
    join public.churches church
      on church.id::text = membership.church_id
      or church."placeId"::text = membership.church_id
    where membership.membership_status = 'active'
      and bounds.church_id in (
        membership.church_id,
        church.id::text,
        church."placeId"::text
      )
      and church.church_status = 'approved'
      -- reviewed_at is when approval actually made the membership active.
      -- Bootstrap memberships without it safely fall back to their creation.
      and coalesce(
        membership.reviewed_at,
        membership.created_at,
        membership.requested_at
      ) <= bounds.scheduled_start
  ) eligible
  on conflict (church_id, user_id, service_id, service_date) do nothing;

  get diagnostics inserted_absences = row_count;

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
    where attendance.church_id = bounds.church_id
      and attendance.service_id = p_service_id
      and attendance.service_date = p_service_date
  )
  insert into public.attendance_finalized_services (
    church_id,
    service_id,
    service_date,
    service_name,
    present_count,
    late_count,
    remote_count,
    absent_count,
    finalized_at
  )
  select
    bounds.church_id,
    p_service_id,
    p_service_date,
    nullif(trim(coalesce(p_service_name, '')), ''),
    totals.present_count,
    totals.late_count,
    totals.remote_count,
    totals.absent_count,
    now()
  from attendance_totals totals
  on conflict (church_id, service_id, service_date) do nothing
  returning true into marker_inserted;

  return jsonb_build_object(
    'finalized', coalesce(marker_inserted, false),
    'reason', case
      when marker_inserted then 'finalized'
      else 'already_finalized'
    end,
    'absences_created', inserted_absences,
    'church_id', bounds.church_id,
    'service_date', p_service_date
  );
end;
$$;

revoke all on function public.finalize_attendance_service_v2(
  text, text, date, text
) from public, anon, authenticated;
grant execute on function public.finalize_attendance_service_v2(
  text, text, date, text
) to service_role;

-- The scheduled Edge job is migrated to the atomic v2 RPC below. Prevent a
-- future caller from accidentally reviving the split absence/finalize flow.
revoke execute on function public.insert_absent_attendance_rows(jsonb)
  from service_role;
revoke execute on function public.finalize_attendance_service(
  text, text, date, text
) from service_role;

-- Care alerts must use the same membership authority and identity as
-- closeout. The legacy implementation unioned users.placeId, preferred a
-- profile uid alias, and measured from account joinDate; all three can flag a
-- removed member or claim they missed services before joining this church.
create or replace function public.refresh_attendance_priority_list(
  p_church_id text,
  p_threshold_weeks integer default null
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  threshold_weeks integer;
  member_row record;
  last_present_at timestamptz;
  baseline_at timestamptz;
  absent_weeks integer;
  open_count integer;
begin
  if nullif(trim(coalesce(p_church_id, '')), '') is null then
    raise exception 'Church is required.' using errcode = '22023';
  end if;

  if coalesce(auth.role(), '') <> 'service_role' and not (
    public.can_manage_church_members(p_church_id)
    or (
      (
        public.get_church_id() = p_church_id
        or public.is_active_member_of(p_church_id)
      )
      and (
        public.has_any_role(array[
          'Pastor',
          'Senior Pastor',
          'Assistant Pastor',
          'Acting Pastor',
          'Admin',
          'Church Admin',
          'Administrator'
        ])
        or public.has_app_privilege('managePriorityList')
        or public.has_app_privilege('viewAttendanceInsights')
      )
    )
  ) then
    raise exception 'Attendance alert management permission is required.'
      using errcode = '42501';
  end if;

  select coalesce(
    p_threshold_weeks,
    settings.absence_threshold_weeks,
    2
  )
    into threshold_weeks
  from (select 1) seed
  left join public.church_attendance_alert_settings settings
    on settings.church_id = p_church_id;
  threshold_weeks := greatest(1, least(26, coalesce(threshold_weeks, 2)));

  for member_row in
    select distinct on (membership.user_id)
      membership.user_id::text as user_id,
      coalesce(nullif(trim(profile."fullName"), ''), 'Member') as user_name,
      coalesce(profile."photoUrl", '') as photo_url,
      coalesce(
        membership.reviewed_at,
        membership.created_at,
        membership.requested_at
      ) as membership_started_at
    from public.church_memberships membership
    join public.churches church
      on church.id::text = membership.church_id
      or church."placeId"::text = membership.church_id
    left join lateral (
      select candidate.*
      from public.users candidate
      where candidate.id = membership.user_id
        or candidate.uid = membership.user_id::text
      order by (candidate.id = membership.user_id) desc
      limit 1
    ) profile on true
    where membership.membership_status = 'active'
      and p_church_id in (
        membership.church_id,
        church.id::text,
        church."placeId"::text
      )
      and church.church_status = 'approved'
    order by
      membership.user_id,
      coalesce(
        membership.reviewed_at,
        membership.created_at,
        membership.requested_at
      ) desc
  loop
    select max(attendance."timestamp")
      into last_present_at
    from public.attendance attendance
    where attendance.user_id = member_row.user_id
      and attendance.present = true
      and attendance."timestamp" >= member_row.membership_started_at
      and (
        attendance.church_id = p_church_id
        or exists (
          select 1
          from public.churches church
          where p_church_id in (church.id::text, church."placeId"::text)
            and attendance.church_id in (
              church.id::text,
              church."placeId"::text
            )
        )
      );

    baseline_at := coalesce(
      last_present_at,
      member_row.membership_started_at,
      now()
    );
    absent_weeks := greatest(
      0,
      floor(extract(epoch from (now() - baseline_at)) / 604800)::integer
    );

    if absent_weeks >= threshold_weeks then
      insert into public.priority_follow_ups (
        "userId",
        "userName",
        "userPhotoUrl",
        "churchId",
        "flaggedAt",
        "absenceStreakWeeks",
        "lastAttendedDate",
        status,
        "updatedAt"
      ) values (
        member_row.user_id,
        member_row.user_name,
        member_row.photo_url,
        p_church_id,
        now(),
        absent_weeks,
        last_present_at,
        'open',
        now()
      )
      on conflict ("churchId", "userId") where status = 'open'
      do update set
        "userName" = excluded."userName",
        "userPhotoUrl" = excluded."userPhotoUrl",
        "absenceStreakWeeks" = excluded."absenceStreakWeeks",
        "lastAttendedDate" = excluded."lastAttendedDate",
        "updatedAt" = now();
    else
      update public.priority_follow_ups follow_up
      set
        status = 'resolved',
        "resolvedAt" = now(),
        "resolvedBy" = case
          when auth.role() = 'service_role' then null
          else auth.uid()::text
        end,
        "updatedAt" = now()
      where follow_up."churchId" = p_church_id
        and follow_up."userId" = member_row.user_id
        and follow_up.status = 'open';
    end if;
  end loop;

  -- Resolve alias-based legacy alerts and alerts for anyone whose active
  -- membership ended. Only the canonical membership auth UUID stays open.
  update public.priority_follow_ups follow_up
  set
    status = 'resolved',
    "resolvedAt" = now(),
    "resolvedBy" = case
      when auth.role() = 'service_role' then null
      else auth.uid()::text
    end,
    "updatedAt" = now()
  where follow_up."churchId" = p_church_id
    and follow_up.status = 'open'
    and not exists (
      select 1
      from public.church_memberships membership
      join public.churches church
        on church.id::text = membership.church_id
        or church."placeId"::text = membership.church_id
      where membership.user_id::text = follow_up."userId"
        and membership.membership_status = 'active'
        and p_church_id in (
          membership.church_id,
          church.id::text,
          church."placeId"::text
        )
        and church.church_status = 'approved'
    );

  select count(*)::integer
    into open_count
  from public.priority_follow_ups follow_up
  where follow_up."churchId" = p_church_id
    and follow_up.status = 'open';

  return coalesce(open_count, 0);
end;
$$;

revoke all on function public.refresh_attendance_priority_list(text, integer)
  from public, anon;
grant execute on function public.refresh_attendance_priority_list(text, integer)
  to authenticated, service_role;

comment on table public.attendance_presence_claims is
  'Server-owned pending/confirmed geofence evidence used to serialize attendance closeout.';
