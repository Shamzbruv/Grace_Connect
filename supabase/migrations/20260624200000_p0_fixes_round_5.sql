-- ============================================================
-- P0 FIXES ROUND 5
-- ============================================================

-- 1. UNIQUE INDEX & SEED FIXES

-- Ensure exactly one active version per document key
create unique index if not exists policy_documents_active_key_idx on public.policy_documents(document_key) where is_active = true;

-- Add 'member_signup' to location_disclosure requirements
update public.policy_documents 
set required_for = array_append(required_for, 'member_signup') 
where document_key = 'location_disclosure' 
  and not ('member_signup' = any(required_for));

-- 2. DYNAMIC POLICY FETCH
create or replace function public.get_active_policy_documents(p_flow_type text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'document_key', document_key,
      'document_version', document_version,
      'title', title,
      'content_url', content_url
    )
  ), '[]'::jsonb)
  from public.policy_documents
  where is_active = true
    and p_flow_type = any(required_for);
$$;
grant execute on function public.get_active_policy_documents(text) to public, anon, authenticated;


-- 3. VERSION-AWARE ENFORCEMENT DRIVEN BY `required_for`
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

  if expected_count = 0 then
    -- No policies required for this flow
    return;
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


-- 4. SUBMIT_CHURCH_REGISTRATION REWRITE
create or replace function public.submit_church_registration(
  church_name text,
  location text default null,
  church_address text default null,
  church_parish text default null,
  denomination uuid default null,
  custom_denomination text default null,
  pastor_full_name text default null,
  pastor_contact_email text default null,
  pastor_contact_phone text default null,
  legal_acceptance uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  actor_email text := auth.jwt()->>'email';
  is_email_confirmed boolean;
  inserted_id uuid;
  denom_code text;
  denom_record record;
  final_church_name text;
begin
  -- Authentication
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Email confirmed
  select (email_confirmed_at is not null) into is_email_confirmed
  from auth.users where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before submitting registration.';
  end if;

  -- Pastor contact email must match authenticated user (case-insensitive)
  if lower(trim(coalesce(pastor_contact_email, ''))) is distinct from lower(trim(coalesce(actor_email, ''))) then
    raise exception 'Pastor contact email must match your verified account email.';
  end if;

  -- Policy enforcement (dynamic flow-based)
  perform public.require_current_policy_acceptances(actor_id, 'church_application');

  -- Validate legal_acceptance against 'church_registration_authority' specifically
  if legal_acceptance is not null then
    if not exists (
      select 1 from public.policy_acceptances pa
      join public.policy_documents pd on pd.document_key = pa.document_key and pd.document_version = pa.document_version
      where pa.id = legal_acceptance
        and pa.user_id = actor_id
        and pa.document_key = 'church_registration_authority'
        and pd.is_active = true
    ) then
      raise exception 'Invalid church_registration_authority acceptance reference.';
    end if;
  else
      raise exception 'A church registration authority declaration acceptance ID is required.';
  end if;

  -- Church name required
  if nullif(trim(coalesce(church_name, '')), '') is null then
    raise exception 'Church name is required.';
  end if;
  final_church_name := trim(church_name);

  -- Parish required
  if nullif(trim(coalesce(church_parish, '')), '') is null then
    raise exception 'Parish is required.';
  end if;

  -- Address required
  if nullif(trim(coalesce(church_address, '')), '') is null then
    raise exception 'Church address is required.';
  end if;

  -- Denomination validation
  if denomination is not null then
    select * into denom_record from public.denominations where id = denomination and is_active = true;
    if denom_record.id is null then
      raise exception 'Invalid or inactive denomination.';
    end if;
    denom_code := denom_record.code;

    -- Custom denomination only allowed for "Other"
    if denom_code <> 'other' and nullif(trim(coalesce(custom_denomination, '')), '') is not null then
      raise exception 'Custom denomination is only allowed when selecting "Other".';
    end if;

    -- Custom denomination required when "Other"
    if denom_code = 'other' and nullif(trim(coalesce(custom_denomination, '')), '') is null then
      raise exception 'Please specify your denomination when selecting "Other".';
    end if;

    -- NTCOG standardization (prevent double suffixes)
    if denom_code = 'ntcog' then
      if nullif(trim(coalesce(location, '')), '') is not null then
         final_church_name := trim(regexp_replace(location, '(?i)\s*(new testament church of god|ntcog)\s*', '', 'g')) || ' NTCOG';
      else
         final_church_name := trim(regexp_replace(final_church_name, '(?i)\s*(new testament church of god|ntcog)\s*', '', 'g')) || ' NTCOG';
      end if;
    end if;
  else
    -- Denomination is required
    raise exception 'Denomination selection is required.';
  end if;

  -- Idempotent: return existing pending application
  select id
    into inserted_id
  from public.church_registration_requests
  where requested_by_user_id = actor_id
    and application_status in (
      'submitted',
      'under_review',
      'needs_information'
    )
  order by created_at desc
  limit 1;

  if inserted_id is not null then
    return inserted_id;
  end if;

  insert into public.church_registration_requests (
    requested_by_user_id,
    church_name_submitted,
    location_name,
    address,
    parish,
    denomination_id,
    custom_denomination_name,
    pastor_name,
    pastor_email,
    pastor_phone,
    legal_acceptance_id
  )
  values (
    actor_id,
    final_church_name,
    nullif(trim(coalesce(location, '')), ''),
    nullif(trim(coalesce(church_address, '')), ''),
    nullif(trim(coalesce(church_parish, '')), ''),
    denomination,
    nullif(trim(coalesce(custom_denomination, '')), ''),
    nullif(trim(coalesce(pastor_full_name, '')), ''),
    nullif(trim(coalesce(pastor_contact_email, '')), ''),
    nullif(trim(coalesce(pastor_contact_phone, '')), ''),
    legal_acceptance
  )
  returning id into inserted_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    'church_registration_submitted',
    jsonb_build_object('requestId', inserted_id, 'churchName', final_church_name)
  );

  return inserted_id;
end;
$$;


-- 5. REQUEST_CHURCH_MEMBERSHIP REWRITE (THROTTLED NOTIFICATIONS)
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
  is_new_request boolean := false;
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

  -- Check if there's already a pending request to throttle notifications
  if not exists (
      select 1
      from public.church_memberships
      where user_id = actor_id
        and church_id = clean_church_id
        and membership_status = 'pending'
  ) then
     is_new_request := true;
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
  on conflict (user_id, church_id)
    where membership_status in ('pending', 'active')
  do update
    set membership_status = 'pending',
        request_message = excluded.request_message,
        requested_at = now(),
        reviewed_by = null,
        reviewed_at = null,
        decision_reason = null,
        removed_by = null,
        removed_at = null,
        removal_reason = null,
        left_at = null
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

  -- Only notify if this is a newly pending request
  if is_new_request then
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
  end if;

  return inserted_id;
end;
$$;
