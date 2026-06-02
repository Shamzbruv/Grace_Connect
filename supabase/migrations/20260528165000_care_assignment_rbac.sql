alter table public.users replica identity full;

alter table public.counseling_requests
  add column if not exists "assignedToHelperId" text;

create index if not exists counseling_requests_assigned_idx
  on public.counseling_requests ("churchId", "assignedToHelperId");

drop policy if exists "Members insert counseling" on public.counseling_requests;
drop policy if exists "Care team view counseling" on public.counseling_requests;
drop policy if exists "Care team update counseling" on public.counseling_requests;

create policy "Members insert counseling"
  on public.counseling_requests
  for insert
  to authenticated
  with check (
    "userId" = auth.uid()::text
    and "churchId" = public.get_church_id()
  );

create policy "Care team view counseling"
  on public.counseling_requests
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      "userId" = auth.uid()::text
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Administrator',
        'Church Admin',
        'Care Counseling Coordinator',
        'Deacon',
        'Deaconess',
        'Elder'
      ])
      or (
        "assignedToHelperId" = auth.uid()::text
        and public.has_any_role(array['Counselor'])
      )
    )
  );

create policy "Care team update counseling"
  on public.counseling_requests
  for update
  to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Administrator',
        'Church Admin',
        'Care Counseling Coordinator',
        'Deacon',
        'Deaconess',
        'Elder'
      ])
      or (
        "assignedToHelperId" = auth.uid()::text
        and public.has_any_role(array['Counselor'])
      )
    )
  )
  with check (
    "churchId" = public.get_church_id()
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Admin',
        'Administrator',
        'Church Admin',
        'Care Counseling Coordinator',
        'Deacon',
        'Deaconess',
        'Elder'
      ])
      or (
        "assignedToHelperId" = auth.uid()::text
        and public.has_any_role(array['Counselor'])
      )
    )
  );

create or replace function public.assign_counseling_helper(
  request_id text,
  helper_uid text default null
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_uid text := auth.uid()::text;
  actor_user_id uuid := auth.uid();
  actor_church_id text := public.get_church_id();
  target_church_id text;
  helper_user_id uuid;
  helper_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not public.has_any_role(array[
    'Pastor',
    'Senior Pastor',
    'Assistant Pastor',
    'Acting Pastor',
    'Admin',
    'Administrator',
    'Church Admin',
    'Care Counseling Coordinator',
    'Deacon',
    'Deaconess',
    'Elder'
  ]) then
    raise exception 'You do not have permission to assign counseling cases';
  end if;

  select "churchId"
    into target_church_id
  from public.counseling_requests
  where id = request_id;

  if target_church_id is null then
    raise exception 'Counseling request not found';
  end if;

  if target_church_id is distinct from actor_church_id then
    raise exception 'You can only assign counseling cases for your church';
  end if;

  if nullif(helper_uid, '') is not null then
    select u.id, coalesce(nullif(u."fullName", ''), u.email)
      into helper_user_id, helper_name
    from public.users u
    where u.uid = helper_uid
      and u."placeId" = target_church_id
      and exists (
        select 1
        from unnest(coalesce(u.roles, '{}'::text[])) as role_name
        where public.normalize_role_name(role_name) = any(array[
          'counselor',
          'care_counseling_coordinator',
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'admin',
          'administrator',
          'church_admin',
          'deacon',
          'deaconess',
          'elder'
        ])
      )
    limit 1;

    if not found then
      raise exception 'Selected helper is not part of your church care team';
    end if;
  end if;

  update public.counseling_requests
  set "assignedToHelperId" = nullif(helper_uid, '')
  where id = request_id
    and "churchId" = target_church_id;

  insert into public.audit_logs ("churchId", action, "performedBy", details)
  values (
    target_church_id,
    'counseling_assigned',
    actor_uid,
    jsonb_build_object(
      'requestId', request_id,
      'assignedTo', nullif(helper_uid, ''),
      'assignedToName', helper_name
    )
  );

  if helper_user_id is not null then
    perform public.create_notification(
      helper_user_id,
      actor_user_id,
      'counseling_assignment',
      'Counseling Case Assigned',
      'A pastoral care request has been assigned to you.',
      target_church_id,
      'counseling_requests',
      request_id,
      '/counseling'
    );
  end if;

  return 'ok';
end;
$$;

create or replace function public.notify_staff_on_counseling_request()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  staff_record record;
  actor_uuid uuid;
begin
  if nullif(new."userId", '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    actor_uuid := new."userId"::uuid;
  end if;

  for staff_record in
    select id
    from public.users u
    where u."placeId" = new."churchId"
      and exists (
        select 1
        from unnest(coalesce(u.roles, '{}'::text[])) as role_name
        where public.normalize_role_name(role_name) = any(array[
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'admin',
          'administrator',
          'church_admin',
          'care_counseling_coordinator',
          'deacon',
          'deaconess',
          'elder'
        ])
      )
  loop
    perform public.create_notification(
      staff_record.id,
      actor_uuid,
      'counseling_request',
      'New Counseling Request',
      coalesce(new.category, 'Pastoral care') || ' request marked ' || coalesce(new.urgency, 'Low'),
      new."churchId",
      'counseling_requests',
      new.id,
      '/counseling'
    );
  end loop;

  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array['users', 'counseling_requests', 'notifications']
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
