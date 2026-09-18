begin;
create temporary table launch_attendance_assertions(description text);
create function pg_temp.check_attendance(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Attendance test failed: %',description; end if;
  insert into launch_attendance_assertions values(description);
end;
$$;
do $test$
declare
  u uuid:=gen_random_uuid();
  c text:='launch_attendance_'||gen_random_uuid()::text;
  services jsonb;
  b record;
  denied boolean;
begin
  insert into auth.users(id,email,aud,role) values(u,u::text||'@audit.invalid','authenticated','authenticated');
  insert into public.churches(id,name,church_status,timezone)
    values(c,'Rollback attendance audit','approved','America/Jamaica');
  insert into public.church_memberships(user_id,church_id,membership_status)
    values(u,c,'active');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  insert into public.service_schedules("serviceId","churchId",name,"dayOfWeek","startTime","endTime")
    values(c||'_school',c,'School',7,'08:30','09:40'),
          (c||'_main',c,'Main',7,'09:50','13:00');
  services:=public.get_my_active_attendance_services(c,'2026-09-13T14:25:00Z');
  perform pg_temp.check_attendance(jsonb_array_length(services->'services')=2,'overlapping services both returned');
  perform pg_temp.check_attendance(services->>'timezone'='America/Jamaica','church timezone returned');
  insert into public.attendance(user_id,church_id,service_id,service_date,timestamp,method,present,status)
    values(u::text,c,c||'_school','2026-09-13','2026-09-13T13:25:00Z','manual',true,'on_time');
  services:=public.get_my_active_attendance_services(c,'2026-09-13T14:25:00Z');
  perform pg_temp.check_attendance(services->'services'->0->>'id'=c||'_main','second service prioritized after school confirmed');
  perform pg_temp.check_attendance((services->'services'->0->>'confirmed')::boolean=false,'second service has independent attendance');
  perform pg_temp.check_attendance((services->'services'->1->>'confirmed')::boolean=true,'school confirmation preserved');
  perform pg_temp.check_attendance((select scheduled_start_at='2026-09-13T13:30:00Z'::timestamptz
    and service_timezone='America/Jamaica' and confirmed_at is not null from public.attendance
    where church_id=c),'schedule and confirmation snapshot created');
  update public.churches set timezone='America/New_York' where id=c;
  select * into b from private.attendance_service_bounds(c,c||'_school','2026-03-01');
  perform pg_temp.check_attendance(b.scheduled_start='2026-03-01T13:30:00Z'::timestamptz,'winter timezone offset');
  select * into b from private.attendance_service_bounds(c,c||'_school','2026-03-08');
  perform pg_temp.check_attendance(b.scheduled_start='2026-03-08T12:30:00Z'::timestamptz,'spring DST timezone offset');
  select * into b from private.attendance_service_bounds(c,c||'_school','2026-11-01');
  perform pg_temp.check_attendance(b.scheduled_start='2026-11-01T13:30:00Z'::timestamptz,'fall DST timezone offset');
  update public.attendance set service_name='School' where church_id=c;
  perform pg_temp.check_attendance((select service_timezone='America/Jamaica'
    and scheduled_start_at='2026-09-13T13:30:00Z'::timestamptz from public.attendance where church_id=c),
    'history snapshot does not change when church timezone changes');
  update public.churches set timezone='Asia/Kolkata' where id=c;
  select * into b from private.attendance_service_bounds(c,c||'_school','2026-09-13');
  perform pg_temp.check_attendance(b.scheduled_start='2026-09-13T03:00:00Z'::timestamptz,'fractional timezone offset');
  update public.churches set timezone='Pacific/Kiritimati' where id=c;
  services:=public.get_my_active_attendance_services(c,'2026-09-12T18:30:00Z');
  perform pg_temp.check_attendance(services->'services'->0->>'serviceDate'='2026-09-13','service date follows church across date line');
  denied:=false;
  begin perform public.get_my_active_attendance_services('another-church',now());
    exception when insufficient_privilege then denied:=true; end;
  perform pg_temp.check_attendance(denied,'cross-church request rejected');
  perform pg_temp.check_attendance(not has_function_privilege('anon',
    'public.get_my_active_attendance_services(text,timestamptz)','EXECUTE'),'anonymous execution denied');
  perform pg_temp.check_attendance(has_function_privilege('authenticated',
    'public.get_my_active_attendance_services(text,timestamptz)','EXECUTE'),'authenticated execution granted');
end;
$test$;
select count(*) as assertions_passed from launch_attendance_assertions;
rollback;

