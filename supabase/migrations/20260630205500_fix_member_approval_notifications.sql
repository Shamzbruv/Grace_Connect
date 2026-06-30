-- Fix developer membership approval locking and route pending member alerts to
-- the actual approval screen.

create or replace function public.developer_approve_member_request(
  p_membership_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target public.church_memberships;
  church_name text;
  target_email text;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  select *
    into target
  from public.church_memberships
  where id::text = trim(coalesce(p_membership_id, ''))
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be approved.';
  end if;

  select coalesce(nullif(display_name, ''), nullif(name, ''), target.church_id)
    into church_name
  from public.churches
  where id = target.church_id or "placeId" = target.church_id
  limit 1;

  update public.church_memberships
     set membership_status = 'active',
         reviewed_by = dev.user_id,
         reviewed_at = now(),
         decision_reason = coalesce(nullif(trim(p_reason), ''), 'Approved from developer portal.')
   where id = target.id;

  update public.church_memberships
     set membership_status = 'cancelled',
         decision_reason = 'Cancelled because another church membership was approved.'
   where user_id = target.user_id
     and id <> target.id
     and membership_status = 'pending';

  update public.users
     set "placeId" = target.church_id,
         "placeName" = coalesce(church_name, target.church_id),
         "accountState" = 'active',
         roles = case when roles is null or array_length(roles, 1) is null then array['Member'] else roles end
   where id = target.user_id
   returning email into target_email;

  insert into public.church_member_roles (membership_id, role_name, assigned_by)
  values (target.id, 'Member', dev.user_id)
  on conflict (membership_id, role_name) do update
    set revoked_at = null,
        assigned_by = excluded.assigned_by,
        assigned_at = now();

  update public.notifications
     set is_read = true
   where entity_table = 'church_memberships'
     and entity_id = target.id::text
     and type = 'membership_request_received';

  begin
    perform public.queue_app_email(
      target_email,
      'Grace Connect membership approved',
      'Your request to join ' || coalesce(church_name, 'your church') || ' was approved. You can now open Grace Connect and use your church features.',
      'Your request to join ' || coalesce(church_name, 'your church') || ' was approved. You can now open Grace Connect and use your church features.',
      'church_membership',
      target.id::text,
      target.user_id,
      jsonb_build_object(
        'type', 'membership_approved',
        'churchId', target.church_id,
        'membershipId', target.id::text,
        'approvedBy', dev.email
      )
    );
  exception when undefined_function then
    null;
  end;

  begin
    perform public.create_notification(
      target.user_id,
      dev.user_id,
      'membership_approved',
      'Membership approved',
      'Your request to join ' || coalesce(church_name, 'this church') || ' was approved.',
      target.church_id,
      'church_memberships',
      target.id::text,
      '/dashboard'
    );
  exception when undefined_function then
    null;
  end;

  perform public.log_developer_action(
    'member_request_approved',
    'church_membership',
    target.id::text,
    jsonb_build_object(
      'userId', target.user_id,
      'churchId', target.church_id,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Approved from developer portal.')
    )
  );

  return jsonb_build_object('ok', true, 'user_id', target.user_id, 'church_id', target.church_id);
end;
$$;

grant execute on function public.developer_approve_member_request(text, text) to authenticated;

create or replace function public.request_church_membership(
  target_church_id text,
  request_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  clean_church_id text := nullif(trim(target_church_id), '');
  is_email_confirmed boolean;
  inserted_id uuid;
  church_name text;
  leader record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select (email_confirmed_at is not null) into is_email_confirmed
  from auth.users
  where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before requesting membership.';
  end if;

  perform public.require_current_policy_acceptances(actor_id, 'member_signup');

  if clean_church_id is null then
    raise exception 'Please select a church.';
  end if;

  select coalesce(nullif(display_name, ''), nullif(name, ''), "placeId", id)
    into church_name
  from public.churches
  where (id = clean_church_id or "placeId" = clean_church_id)
    and church_status = 'approved'
    and public_visibility = true
  limit 1;

  if church_name is null then
    raise exception 'This church is not approved for membership requests.';
  end if;

  if exists (
    select 1
    from public.church_memberships
    where user_id = actor_id
      and membership_status = 'active'
  ) then
    raise exception 'You already have an active church membership.';
  end if;

  select id into inserted_id
  from public.church_memberships
  where user_id = actor_id
    and church_id = clean_church_id
    and membership_status = 'pending';

  if inserted_id is not null then
    raise exception 'Your request is already pending.';
  end if;

  insert into public.church_memberships (
    user_id,
    church_id,
    membership_status,
    request_message
  )
  values (
    actor_id,
    clean_church_id,
    'pending',
    nullif(trim(coalesce(request_note, '')), '')
  )
  returning id into inserted_id;

  update public.users
     set "accountState" = 'pending',
         "placeId" = null,
         "placeName" = null,
         roles = array['Member']
   where id = actor_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    clean_church_id,
    'membership_requested',
    jsonb_build_object('churchName', church_name)
  );

  for leader in
    select distinct cm.user_id as id
    from public.church_memberships cm
    join public.church_member_roles cmr on cmr.membership_id = cm.id
    where cm.church_id = clean_church_id
      and cm.membership_status = 'active'
      and cmr.revoked_at is null
      and public.normalize_role_name(cmr.role_name) in (
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor',
        'church_admin',
        'admin',
        'administrator',
        'secretary',
        'church_secretary'
      )
  loop
    begin
      perform public.create_notification(
        leader.id,
        actor_id,
        'membership_request_received',
        'New membership request',
        'A member requested to join ' || church_name || '.',
        clean_church_id,
        'church_memberships',
        inserted_id::text,
        '/membership_requests'
      );
    exception when undefined_function then
      null;
    end;
  end loop;

  return inserted_id;
end;
$$;

grant execute on function public.request_church_membership(text, text) to authenticated;

create or replace function public.approve_church_membership(
  membership_id uuid,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target record;
  church_name text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target
  from public.church_memberships
  where id = membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.user_id = actor_id then
    raise exception 'You cannot approve your own membership.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be approved.';
  end if;

  if not public.can_manage_church_members(target.church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  update public.church_memberships
     set membership_status = 'active',
         reviewed_by = actor_id,
         reviewed_at = now(),
         decision_reason = nullif(trim(coalesce(decision_note, '')), '')
   where id = membership_id;

  update public.church_memberships
     set membership_status = 'cancelled',
         decision_reason = 'Cancelled because another church membership was approved.'
   where user_id = target.user_id
     and id <> membership_id
     and membership_status = 'pending';

  select coalesce(nullif(display_name, ''), nullif(name, ''), target.church_id)
    into church_name
  from public.churches
  where id = target.church_id or "placeId" = target.church_id
  limit 1;

  update public.users
     set "placeId" = target.church_id,
         "placeName" = coalesce(church_name, target.church_id),
         "accountState" = 'active',
         roles = case
           when roles is null or array_length(roles, 1) is null then array['Member']
           else roles
         end
   where id = target.user_id;

  insert into public.church_member_roles (membership_id, role_name, assigned_by)
  values (membership_id, 'Member', actor_id)
  on conflict (membership_id, role_name) do update
    set revoked_at = null,
        assigned_by = excluded.assigned_by,
        assigned_at = now();

  update public.notifications
     set is_read = true
   where entity_table = 'church_memberships'
     and entity_id = membership_id::text
     and type = 'membership_request_received';

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    target.user_id,
    target.church_id,
    'membership_approved',
    jsonb_build_object('reason', nullif(trim(coalesce(decision_note, '')), ''))
  );

  begin
    perform public.create_notification(
      target.user_id,
      actor_id,
      'membership_approved',
      'Membership approved',
      'Your request to join ' || coalesce(church_name, 'this church') || ' was approved.',
      target.church_id,
      'church_memberships',
      membership_id::text,
      '/dashboard'
    );
  exception when undefined_function then
    null;
  end;
end;
$$;

grant execute on function public.approve_church_membership(uuid, text) to authenticated;

create or replace function public.decline_church_membership(
  membership_id uuid,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target
  from public.church_memberships
  where id = membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.user_id = actor_id then
    raise exception 'You cannot decline your own membership.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be declined.';
  end if;

  if not public.can_manage_church_members(target.church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  update public.church_memberships
     set membership_status = 'declined',
         reviewed_by = actor_id,
         reviewed_at = now(),
         decision_reason = nullif(trim(coalesce(decision_note, '')), '')
   where id = membership_id;

  update public.users
     set "accountState" = 'declined',
         "placeId" = null,
         "placeName" = null,
         roles = array['Member']
   where id = target.user_id
     and not exists (
       select 1
       from public.church_memberships
       where user_id = target.user_id
         and membership_status = 'active'
     );

  update public.notifications
     set is_read = true
   where entity_table = 'church_memberships'
     and entity_id = membership_id::text
     and type = 'membership_request_received';

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  )
  values (
    actor_id,
    target.user_id,
    target.church_id,
    'membership_declined',
    jsonb_build_object('reason', nullif(trim(coalesce(decision_note, '')), ''))
  );

  begin
    perform public.create_notification(
      target.user_id,
      actor_id,
      'membership_declined',
      'Membership request declined',
      'Your church membership request was declined.',
      target.church_id,
      'church_memberships',
      membership_id::text,
      '/'
    );
  exception when undefined_function then
    null;
  end;
end;
$$;

grant execute on function public.decline_church_membership(uuid, text) to authenticated;
