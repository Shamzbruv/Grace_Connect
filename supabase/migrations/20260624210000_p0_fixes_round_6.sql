-- ============================================================
-- P0 FIXES ROUND 6
-- ============================================================

-- 1. REQUIRE_CURRENT_POLICY_ACCEPTANCES (FAIL CLOSED)
create or replace function public.require_current_policy_acceptances(
  actor_id uuid,
  flow_type text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  missing_keys text[];
  expected_count int;
begin
  select count(*) into expected_count
  from public.policy_documents
  where is_active = true
    and flow_type = any(required_for);

  -- Fail closed: if no active policies are configured, throw configuration error
  if expected_count = 0 then
    raise exception 'Policy configuration error: no active policies configured for %', flow_type;
  end if;

  select array_agg(pd.document_key)
  into missing_keys
  from public.policy_documents pd
  where pd.is_active = true
    and flow_type = any(pd.required_for)
    and not exists (
      select 1
      from public.policy_acceptances pa
      where pa.user_id = actor_id
        and pa.document_key = pd.document_key
        and pa.document_version = pd.document_version
    );

  if missing_keys is not null and array_length(missing_keys, 1) > 0 then
    raise exception 'Missing or outdated policy acceptances for %: %', flow_type, array_to_string(missing_keys, ', ');
  end if;
end;
$$;


-- 2. REQUEST_CHURCH_MEMBERSHIP (DO NOT RESET QUEUE)
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

  -- Email confirmed
  select (email_confirmed_at is not null) into is_email_confirmed
  from auth.users where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before requesting membership.';
  end if;

  -- Policy enforcement (dynamic flow-based)
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

  -- Prevent queue reset: if a pending request exists, halt and notify user
  select id into inserted_id
  from public.church_memberships
  where user_id = actor_id
    and church_id = clean_church_id
    and membership_status = 'pending';
    
  if inserted_id is not null then
    raise exception 'Your request is already pending.';
  end if;

  -- Insert new pending request
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

  -- Notify leaders for this new request
  for leader in
    select cm.user_id as id
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
        '/members'
      );
    exception when undefined_function then
      null;
    end;
  end loop;

  return inserted_id;
end;
$$;
