-- Explicit app privilege grants for dynamic role assignments.
alter table public.users
  add column if not exists "appPrivileges" text[] not null default '{}'::text[];

create or replace function public.assign_member_privileges(
  target_uid text,
  privilege_names text[],
  church_id text
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_church_id text := public.get_church_id();
  cleaned_privileges text[];
  actor_name text;
  target_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if church_id is null or actor_church_id is distinct from church_id then
    raise exception 'You can only manage privileges for your church';
  end if;

  if not public.has_any_role(array['Pastor', 'Senior Pastor']) then
    raise exception 'Only the Pastor and Senior Pastor can assign privileges';
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

  select coalesce(array_agg(distinct clean_value), '{}'::text[])
    into cleaned_privileges
    from (
      select trim(value) as clean_value
      from unnest(coalesce(privilege_names, '{}'::text[])) as value
      where trim(value) <> ''
    ) cleaned;

  update public.users
  set "appPrivileges" = cleaned_privileges
  where uid = target_uid;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    church_id,
    'privileges_updated',
    actor_uid,
    jsonb_build_object(
      'targetUid', target_uid,
      'targetName', target_name,
      'performedByName', coalesce(actor_name, actor_uid),
      'privilegesAfter', cleaned_privileges,
      'context',
        coalesce(actor_name, 'A leader') || ' updated app privileges for ' ||
        target_name
    )
  );

  begin
    perform public.create_notification(
      target_uid::uuid,
      actor_uid::uuid,
      'role_changed',
      'Access updated',
      'Your Grace Connect app access privileges were updated.',
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

grant execute on function public.assign_member_privileges(text, text[], text)
  to authenticated;
