-- Attendance windows and readable role history details.

alter table if exists public.service_schedules
  add column if not exists recurrence text not null default 'weekly',
  add column if not exists "attendanceEnabled" boolean not null default true,
  add column if not exists "checkInOpensMinutesBefore" integer not null default 30,
  add column if not exists "checkInClosesMinutesAfter" integer not null default 30,
  add column if not exists "minimumDwellMinutes" integer not null default 10;

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
  next_roles text[];
  notification_action text;
  actor_name text;
  target_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage roles for your church';
  end if;

  if not public.has_any_role(array['Pastor', 'Senior Pastor']) then
    raise exception 'Only the Pastor and Senior Pastor can assign roles';
  end if;

  select coalesce(nullif("fullName", ''), nullif(email, ''), actor_uid)
    into actor_name
    from public.users
    where uid = actor_uid
    limit 1;

  select coalesce(nullif("fullName", ''), nullif(email, ''), target_uid)
    into target_name
    from public.users
    where uid = target_uid
      and "placeId" = church_id
    limit 1;

  if target_name is null then
    raise exception 'Target member was not found in your church';
  end if;

  if lower(coalesce(role_action, 'add')) = 'remove' then
    update public.users
    set roles = array_remove(coalesce(roles, '{}'::text[]), role_name)
    where uid = target_uid
    returning roles into next_roles;
    notification_action := 'removed';
  else
    update public.users
    set roles = (
      select array_agg(distinct role_value)
      from unnest(coalesce(roles, '{}'::text[]) || role_name) as role_value
    )
    where uid = target_uid
    returning roles into next_roles;
    notification_action := 'assigned';
  end if;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    church_id,
    case when notification_action = 'removed'
      then 'role_removed'
      else 'role_assigned'
    end,
    actor_uid,
    jsonb_build_object(
      'targetUid', target_uid,
      'targetName', target_name,
      'performedByName', coalesce(actor_name, actor_uid),
      'roleChanged', role_name,
      'rolesAfter', next_roles,
      'context',
        coalesce(actor_name, 'A leader') || ' ' || notification_action ||
        ' ' || role_name || ' for ' || target_name
    )
  );

  begin
    perform public.create_notification(
      target_uid::uuid,
      actor_uid::uuid,
      'role_changed',
      'Role updated',
      'Your ' || role_name || ' role was ' || notification_action || '.',
      church_id,
      'users',
      target_uid,
      '/notifications'
    );
  exception when others then
    null;
  end;

  return 'ok';
end;
$$;

grant execute on function public.assign_member_role(text, text, text, text)
  to authenticated;
