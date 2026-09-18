-- Church clocks and immutable schedule context. Do not regrade old arrivals.
create or replace function private.church_timezone(p_church_id text)
returns text language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select nullif(trim(c.timezone),'') from public.churches c
    where p_church_id in (c.id::text, c."placeId"::text)
    order by (c.id::text = p_church_id) desc limit 1
  ), 'UTC');
$$;
revoke all on function private.church_timezone(text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.attendance_service_bounds(p_church_id text, p_service_id text, p_service_date date)
 RETURNS TABLE(church_id text, service_date date, scheduled_start timestamp with time zone, scheduled_end timestamp with time zone, check_in_opens timestamp with time zone, check_in_closes timestamp with time zone, required_dwell_seconds integer, ready_to_finalize_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  schedule_row public.service_schedules%rowtype;
  local_start timestamp;
  local_end timestamp;
  local_opens timestamp;
  local_closes timestamp;
  dwell_seconds integer;
  church_zone text := private.church_timezone(p_church_id);
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
    local_start at time zone church_zone,
    local_end at time zone church_zone,
    (local_start at time zone church_zone) - make_interval(mins => greatest(0, least(240, coalesce(schedule_row."checkInOpensMinutesBefore",30)))),
    (local_end at time zone church_zone) + make_interval(mins => greatest(0, least(240, coalesce(schedule_row."checkInClosesMinutesAfter",30)))),
    dwell_seconds,
    (local_end at time zone church_zone)
      + make_interval(mins => greatest(0, least(240, coalesce(schedule_row."checkInClosesMinutesAfter",30))))
      + make_interval(secs => dwell_seconds) + interval '15 minutes';
end;
$function$;

create or replace function private.attendance_service_occurrence(
  p_church_id text, p_service_id text, p_observed_at timestamptz)
returns table(church_id text, service_date date, scheduled_start timestamptz,
  scheduled_end timestamptz, check_in_opens timestamptz, check_in_closes timestamptz,
  required_dwell_seconds integer, ready_to_finalize_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  with dates as (
    select (p_observed_at at time zone private.church_timezone(p_church_id))::date + d as day
    from generate_series(-1, 1) d
  )
  select b.* from dates cross join lateral
    private.attendance_service_bounds(p_church_id,p_service_id,dates.day) b
  where p_observed_at >= b.check_in_opens and p_observed_at < b.check_in_closes
  order by b.scheduled_start desc limit 1;
$$;
revoke all on function private.attendance_service_occurrence(text,text,timestamptz)
  from public,anon,authenticated;
revoke all on function private.attendance_service_bounds(text,text,date)
  from public,anon,authenticated;

alter table public.attendance
  add column if not exists service_timezone text,
  add column if not exists scheduled_start_at timestamptz,
  add column if not exists confirmed_at timestamptz;

-- Existing rows gain display context only. Arrival, grading and absence history
-- are deliberately unchanged. An unknown deleted schedule stays unknown.
update public.attendance a set
  service_timezone=private.church_timezone(a.church_id),
  scheduled_start_at=(select b.scheduled_start from
    private.attendance_service_bounds(a.church_id,a.service_id,a.service_date) b),
  confirmed_at=case when a.present then coalesce((
    select p.confirmed_at from public.attendance_presence_claims p
    where p.user_id=a.user_id and p.church_id=a.church_id
      and p.service_id=a.service_id and p.service_date=a.service_date
  ),a.timestamp) else null end
where a.service_timezone is null;

create or replace function private.snapshot_attendance_schedule()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if TG_OP='INSERT' or NEW.service_id is distinct from OLD.service_id
      or NEW.church_id is distinct from OLD.church_id
      or NEW.service_date is distinct from OLD.service_date then
    NEW.service_timezone := private.church_timezone(NEW.church_id);
    select b.scheduled_start into NEW.scheduled_start_at
      from private.attendance_service_bounds(NEW.church_id,NEW.service_id,NEW.service_date) b;
  else
    NEW.service_timezone := OLD.service_timezone;
    NEW.scheduled_start_at := OLD.scheduled_start_at;
  end if;
  if NEW.present and (TG_OP='INSERT' or not coalesce(OLD.present,false)) then
    NEW.confirmed_at := now();
  elsif TG_OP='UPDATE' then
    NEW.confirmed_at := OLD.confirmed_at;
  end if;
  return NEW;
end;
$$;
revoke all on function private.snapshot_attendance_schedule() from public,anon,authenticated;
create trigger attendance_schedule_snapshot before insert or update on public.attendance
for each row execute function private.snapshot_attendance_schedule();

create or replace function public.get_my_active_attendance_services(
  p_church_id text, p_observed_at timestamptz default now())
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  zone text := private.church_timezone(p_church_id);
  items jsonb;
begin
  if actor is null or not private.is_active_attendance_member(actor,p_church_id) then
    raise exception 'Active church membership is required.' using errcode='42501';
  end if;
  if p_observed_at is null then raise exception 'Observation time is required.'; end if;
  with dates as (
    select (p_observed_at at time zone zone)::date+d as day
      from generate_series(-1,1) d
  ), candidates as (
    select s."serviceId",s.name,s."startTime",b.*,
      a.present is true as confirmed,
      p.first_inside_at,
      p_observed_at>=b.check_in_closes as completion_only
    from public.service_schedules s
    cross join dates
    cross join lateral private.attendance_service_bounds(
      p_church_id,s."serviceId",dates.day) b
    left join public.attendance a on a.user_id=actor::text
      and a.church_id=b.church_id and a.service_id=s."serviceId"
      and a.service_date=b.service_date
    left join public.attendance_presence_claims p on p.user_id=actor::text
      and p.church_id=b.church_id and p.service_id=s."serviceId"
      and p.service_date=b.service_date and p.status='pending'
    where s."attendanceEnabled"=true
      and s."churchId" in (select c.id::text from public.churches c
        where p_church_id in(c.id::text,c."placeId"::text)
        union select c."placeId"::text from public.churches c
        where p_church_id in(c.id::text,c."placeId"::text))
      and p_observed_at>=b.check_in_opens
      and (p_observed_at<b.check_in_closes or
        (p.first_inside_at>=b.check_in_opens and p.first_inside_at<b.check_in_closes
         and p_observed_at<=b.ready_to_finalize_at))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',"serviceId",'churchId',church_id,'name',name,'startTime',"startTime",
    'serviceDate',service_date,'serviceDateAnchor',scheduled_start,
    'checkInOpens',check_in_opens,
    'checkInCloses',case when completion_only then ready_to_finalize_at else check_in_closes end,
    'minimumDwellMinutes',required_dwell_seconds/60,'confirmed',confirmed,
    'completionOnly',completion_only,'arrivalTime',first_inside_at
  ) order by confirmed asc, (scheduled_start>p_observed_at) asc,
      scheduled_start desc,"serviceId"),'[]'::jsonb) into items from candidates;
  return jsonb_build_object('timezone',zone,'services',items);
end;
$$;
revoke all on function public.get_my_active_attendance_services(text,timestamptz)
  from public,anon;
grant execute on function public.get_my_active_attendance_services(text,timestamptz)
  to authenticated;
