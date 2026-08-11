-- Attendance reliability repair.
--
-- 1. Makes member check-in idempotent, including offline retries and races
--    between manual and automatic check-in.
-- 2. Moves attendance care-alert refresh into one atomic server operation so
--    the partial unique index can never blank the client with a 23505.
-- 3. Gives the scheduled finalizer an idempotent batch path for absences.

create extension if not exists pgcrypto;

-- Retain the best row if historical retries created more than one attendance
-- record for the same member/service/Jamaica calendar day.
with ranked_attendance as (
  select
    ctid,
    row_number() over (
      partition by
        church_id,
        user_id,
        service_id,
        (("timestamp" at time zone 'America/Jamaica')::date)
      order by present desc, "timestamp" asc, id asc
    ) as row_number
  from public.attendance
)
delete from public.attendance attendance_row
using ranked_attendance duplicate
where attendance_row.ctid = duplicate.ctid
  and duplicate.row_number > 1;

create unique index if not exists
  attendance_one_record_per_member_service_day_idx
on public.attendance (
  church_id,
  user_id,
  service_id,
  (("timestamp" at time zone 'America/Jamaica')::date)
);

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
set search_path = public, pg_temp
as $$
declare
  caller_id text := auth.uid()::text;
  attendance_id public.attendance.id%type;
  was_inserted boolean := false;
  attendance_timestamp timestamptz := coalesce(p_timestamp, now());
  attendance_date date :=
    (coalesce(p_timestamp, now()) at time zone 'America/Jamaica')::date;
begin
  if caller_id is null or caller_id = '' then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or nullif(trim(coalesce(p_service_id, '')), '') is null then
    raise exception 'Church and service are required.' using errcode = '22023';
  end if;

  if not (
    public.get_church_id() = p_church_id
    or exists (
      select 1
      from public.users u
      where (u.id::text = caller_id or u.uid = caller_id)
        and u."placeId" = p_church_id
        and coalesce(u."accountState", 'active') not in (
          'disabled', 'suspended', 'deleted', 'deletion_requested', 'removed'
        )
    )
  ) then
    raise exception 'Attendance must be recorded for your active church.'
      using errcode = '42501';
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

  if not exists (
    select 1
    from public.service_schedules schedule
    where schedule."serviceId" = p_service_id
      and schedule."churchId" = p_church_id
      and coalesce(schedule."attendanceEnabled", true) = true
  ) then
    raise exception 'The attendance service is not configured for this church.'
      using errcode = '22023';
  end if;

  -- Serialize member check-ins with finalization for this exact service day.
  -- Without this lock, an offline promotion can commit immediately after the
  -- finalizer's count snapshot but before its durable marker is inserted.
  perform pg_advisory_xact_lock(hashtextextended(
    concat(
      'grace-attendance:', p_church_id, ':', p_service_id, ':',
      attendance_date
    ),
    0
  ));

  insert into public.attendance as existing (
    user_id,
    church_id,
    service_id,
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
    p_church_id,
    p_service_id,
    attendance_timestamp,
    p_method,
    true,
    p_status,
    p_minutes_late,
    p_reason_for_absence,
    p_engagement_answer,
    p_service_name
  )
  on conflict (
    church_id,
    user_id,
    service_id,
    (("timestamp" at time zone 'America/Jamaica')::date)
  ) do update set
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
    where attendance.church_id = p_church_id
      and attendance.user_id = caller_id
      and attendance.service_id = p_service_id
      and (attendance."timestamp" at time zone 'America/Jamaica')::date =
          attendance_date
    order by attendance.present desc, attendance."timestamp" asc
    limit 1;
  end if;

  -- A phone can reconnect after the closeout job created an auto_absent row.
  -- Keep the finalized dashboard and its in-app report consistent when that
  -- placeholder is promoted to a legitimate offline/manual check-in.
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
      and (attendance."timestamp" at time zone 'America/Jamaica')::date =
          attendance_date
  )
  update public.attendance_finalized_services finalized
     set present_count = totals.present_count,
         late_count = totals.late_count,
         remote_count = totals.remote_count,
         absent_count = totals.absent_count,
         finalized_at = now()
    from attendance_totals totals
   where finalized.church_id = p_church_id
     and finalized.service_id = p_service_id
     and finalized.service_date = attendance_date;

  update public.notifications notification
     set body = concat(
       finalized.present_count, ' present • ',
       finalized.late_count, ' late • ',
       finalized.remote_count, ' remote • ',
       finalized.absent_count, ' absent for ',
       finalized.service_date, '.'
     )
    from public.attendance_finalized_services finalized
   where finalized.church_id = p_church_id
     and finalized.service_id = p_service_id
     and finalized.service_date = attendance_date
     and notification.entity_table = 'attendance_finalized_services'
     and notification.entity_id = concat(
       finalized.church_id, ':', finalized.service_id, ':',
       finalized.service_date
     );

  return jsonb_build_object(
    'id', attendance_id::text,
    'inserted', was_inserted
  );
end;
$$;

revoke all on function public.record_my_attendance(
  text, text, timestamptz, text, boolean, text, integer, text, text, text
) from public, anon;
grant execute on function public.record_my_attendance(
  text, text, timestamptz, text, boolean, text, integer, text, text, text
) to authenticated;

-- Claiming the finalized row and creating every leader notification happens
-- in one transaction. Concurrent cron runs cannot both claim it, and an insert
-- failure rolls report_sent_at back so the next cron run can retry safely.
create or replace function public.send_attendance_finalized_report(
  p_church_id text,
  p_service_id text,
  p_service_date date,
  p_leader_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  finalized public.attendance_finalized_services%rowtype;
  inserted_count integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required.' using errcode = '42501';
  end if;

  if cardinality(coalesce(p_leader_ids, '{}'::uuid[])) = 0 then
    return 0;
  end if;

  update public.attendance_finalized_services attendance_service
  set report_sent_at = now()
  where attendance_service.church_id = p_church_id
    and attendance_service.service_id = p_service_id
    and attendance_service.service_date = p_service_date
    and attendance_service.report_sent_at is null
  returning attendance_service.* into finalized;

  if not found then
    return 0;
  end if;

  insert into public.notifications (
    user_id,
    actor_id,
    actor_name,
    type,
    title,
    body,
    place_id,
    entity_table,
    entity_id,
    route
  )
  select
    leaders.user_id,
    null,
    'Grace Connect',
    'attendance_report',
    'Sunday School Attendance Ready',
    concat(
      finalized.present_count, ' present • ',
      finalized.late_count, ' late • ',
      finalized.remote_count, ' remote • ',
      finalized.absent_count, ' absent for ',
      finalized.service_date, '.'
    ),
    finalized.church_id,
    'attendance_finalized_services',
    concat(
      finalized.church_id, ':', finalized.service_id, ':',
      finalized.service_date
    ),
    '/attendance_insights'
  from (
    select distinct unnest(p_leader_ids) as user_id
  ) leaders
  where leaders.user_id is not null;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.send_attendance_finalized_report(
  text, text, date, uuid[]
) from public, anon, authenticated;
grant execute on function public.send_attendance_finalized_report(
  text, text, date, uuid[]
) to service_role;

create or replace function public.insert_absent_attendance_rows(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted_count integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Service role required.' using errcode = '42501';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return 0;
  end if;

  insert into public.attendance (
    user_id,
    church_id,
    service_id,
    "timestamp",
    method,
    present,
    status,
    service_name
  )
  select
    row_data.user_id,
    row_data.church_id,
    row_data.service_id,
    row_data."timestamp",
    'auto_absent',
    false,
    'absent',
    row_data.service_name
  from jsonb_to_recordset(p_rows) as row_data(
    user_id text,
    church_id text,
    service_id text,
    "timestamp" timestamptz,
    service_name text
  )
  where nullif(trim(row_data.user_id), '') is not null
    and nullif(trim(row_data.church_id), '') is not null
    and nullif(trim(row_data.service_id), '') is not null
  on conflict do nothing;

  get diagnostics inserted_count = row_count;
  return inserted_count;
end;
$$;

revoke all on function public.insert_absent_attendance_rows(jsonb)
  from public, anon, authenticated;
grant execute on function public.insert_absent_attendance_rows(jsonb)
  to service_role;

-- Finalization and member check-in take the same transaction-level advisory
-- lock. Counts are derived from durable attendance rows inside the marker
-- transaction, so a concurrent offline check-in is always reflected either
-- here or by record_my_attendance immediately afterward.
create or replace function public.finalize_attendance_service(
  p_church_id text,
  p_service_id text,
  p_service_date date,
  p_service_name text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  marker_inserted boolean := false;
begin
  if auth.role() <> 'service_role' then
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
      and (attendance."timestamp" at time zone 'America/Jamaica')::date =
          p_service_date
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

create or replace function public.refresh_attendance_priority_list(
  p_church_id text,
  p_threshold_weeks integer default null
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
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

  if auth.role() <> 'service_role' and not (
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
    select distinct on (coalesce(nullif(u.uid, ''), u.id::text))
      coalesce(nullif(u.uid, ''), u.id::text) as user_id,
      coalesce(nullif(trim(u."fullName"), ''), 'Member') as user_name,
      coalesce(u."photoUrl", '') as photo_url,
      coalesce(u."joinDate", membership.requested_at, now()) as joined_at,
      u.id::text as alternate_user_id
    from public.users u
    left join lateral (
      select min(cm.requested_at) as requested_at
      from public.church_memberships cm
      where cm.user_id = u.id
        and cm.church_id = p_church_id
        and cm.membership_status = 'active'
    ) membership on true
    where (
      u."placeId" = p_church_id
      or membership.requested_at is not null
    )
      and coalesce(u."accountState", 'active') not in (
        'disabled', 'suspended', 'deleted', 'deletion_requested', 'removed'
      )
    order by coalesce(nullif(u.uid, ''), u.id::text), u."joinDate" desc nulls last
  loop
    select max(attendance."timestamp")
      into last_present_at
    from public.attendance attendance
    where attendance.church_id = p_church_id
      and attendance.present = true
      and attendance.user_id in (
        member_row.user_id,
        member_row.alternate_user_id
      );

    baseline_at := coalesce(last_present_at, member_row.joined_at, now());
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

  -- Retired, removed, or transferred members must not leave stale open alerts.
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
      from public.users u
      where coalesce(nullif(u.uid, ''), u.id::text) = follow_up."userId"
        and coalesce(u."accountState", 'active') not in (
          'disabled', 'suspended', 'deleted', 'deletion_requested', 'removed'
        )
        and (
          u."placeId" = p_church_id
          or exists (
            select 1
            from public.church_memberships cm
            where cm.user_id = u.id
              and cm.church_id = p_church_id
              and cm.membership_status = 'active'
          )
        )
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

-- Align database access with the same role/privilege gates used by the app.
drop policy if exists "Pastors and admins manage attendance alert settings"
  on public.church_attendance_alert_settings;
create policy "Pastors and admins manage attendance alert settings"
  on public.church_attendance_alert_settings
  for all
  to authenticated
  using (
    public.can_manage_church_members(church_id)
    or (
      (public.get_church_id() = church_id or public.is_active_member_of(church_id))
      and public.has_app_privilege('managePriorityList')
    )
  )
  with check (
    public.can_manage_church_members(church_id)
    or (
      (public.get_church_id() = church_id or public.is_active_member_of(church_id))
      and public.has_app_privilege('managePriorityList')
    )
  );

drop policy if exists "Church members view open attendance care alerts"
  on public.priority_follow_ups;
create policy "Church members view open attendance care alerts"
  on public.priority_follow_ups
  for select
  to authenticated
  using (
    status = 'open'
    and (
      "churchId" = public.get_church_id()
      or public.is_active_member_of("churchId")
    )
  );

drop policy if exists "Pastors and admins manage attendance care alerts"
  on public.priority_follow_ups;
create policy "Pastors and admins manage attendance care alerts"
  on public.priority_follow_ups
  for all
  to authenticated
  using (
    public.can_manage_church_members("churchId")
    or (
      (
        public.get_church_id() = "churchId"
        or public.is_active_member_of("churchId")
      )
      and public.has_app_privilege('managePriorityList')
    )
  )
  with check (
    public.can_manage_church_members("churchId")
    or (
      (
        public.get_church_id() = "churchId"
        or public.is_active_member_of("churchId")
      )
      and public.has_app_privilege('managePriorityList')
    )
  );
