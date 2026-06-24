-- 1. Helper for enforcing policy acceptances
create or replace function public.require_current_policy_acceptances(
  actor_id uuid,
  required_keys text[]
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  missing_keys text[];
begin
  select array_agg(k.key)
  into missing_keys
  from unnest(required_keys) as k(key)
  left join public.policy_acceptances pa 
    on pa.user_id = actor_id 
    and pa.document_key = k.key
  where pa.id is null;

  if array_length(missing_keys, 1) > 0 then
    raise exception 'Missing policy acceptances: %', array_to_string(missing_keys, ', ');
  end if;
end;
$$;

grant execute on function public.require_current_policy_acceptances(uuid, text[]) to authenticated;

-- 2. Update submit_church_registration
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
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select (email_confirmed_at is not null) into is_email_confirmed
  from auth.users where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before submitting registration.';
  end if;

  if pastor_contact_email is distinct from actor_email then
    raise exception 'Pastor contact email must match your verified account email.';
  end if;

  perform public.require_current_policy_acceptances(actor_id, array[
    'terms',
    'privacy',
    'community_guidelines',
    'age_policy',
    'church_admin_access',
    'church_registration_authority',
    'data_retention'
  ]);

  if nullif(trim(coalesce(church_name, '')), '') is null then
    raise exception 'Church name is required.';
  end if;

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
    trim(church_name),
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
    jsonb_build_object('requestId', inserted_id, 'churchName', trim(church_name))
  );

  return inserted_id;
end;
$$;

-- 3. Update request_church_membership
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
  from auth.users where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before requesting membership.';
  end if;

  perform public.require_current_policy_acceptances(actor_id, array[
    'terms',
    'privacy',
    'community_guidelines',
    'age_policy',
    'location_disclosure'
  ]);

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
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    'church_membership_requested',
    jsonb_build_object('requestId', inserted_id, 'churchId', clean_church_id, 'churchName', church_name)
  );

  return inserted_id;
end;
$$;
