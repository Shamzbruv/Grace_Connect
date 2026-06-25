-- Round 7 P0 Fixes
-- 1. Add new developer roles
alter table public.developer_accounts drop constraint if exists developer_accounts_role_check;
alter table public.developer_accounts add constraint developer_accounts_role_check check (
    developer_role in (
      'super_developer',
      'support_developer',
      'security_admin',
      'read_only_support',
      'content_moderator',
      'billing_support'
    )
);

-- 2. Add applicant_note to church_registration_requests
alter table public.church_registration_requests add column if not exists applicant_note text;

-- 3. Update submit_church_registration
create or replace function public.submit_church_registration(
  p_church_name text,
  p_location_name text,
  p_address text,
  p_parish text,
  p_denomination_id uuid,
  p_custom_denomination text,
  p_pastor_full_name text,
  p_pastor_contact_email text,
  p_pastor_contact_phone text,
  p_legal_acceptance uuid,
  p_applicant_note text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_user_id uuid;
  v_church_id uuid;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Ensure email is verified
  if not exists (
    select 1 from auth.users
    where id = v_user_id
      and email_confirmed_at is not null
  ) then
    raise exception 'Email must be verified before submitting a church registration.';
  end if;

  -- Enforce safe inputs
  if length(trim(p_church_name)) < 3 then
    raise exception 'Church name is too short';
  end if;
  
  if p_parish is null or trim(p_parish) = '' then
    raise exception 'Parish is required';
  end if;
  
  if p_address is null or trim(p_address) = '' then
    raise exception 'Address is required';
  end if;

  -- 1. Validate the legal acceptance record belongs to this user and is for church registration
  if not exists (
    select 1 from public.legal_acceptances
    where id = p_legal_acceptance
      and user_id = v_user_id
      and document_key = 'church_registration_authority'
  ) then
    raise exception 'Invalid or missing legal authority acceptance.';
  end if;

  -- 2. Check for duplicate pending requests by this user to prevent queue spamming
  if exists (
    select 1 from public.church_registration_requests
    where requested_by_user_id = v_user_id
      and application_status in ('submitted', 'under_review', 'needs_information')
  ) then
    raise exception 'You already have a pending church registration request.';
  end if;

  -- 3. Insert the registration request
  insert into public.church_registration_requests (
    requested_by_user_id,
    church_name,
    location_name,
    address,
    parish,
    denomination_id,
    custom_denomination,
    pastor_full_name,
    pastor_contact_email,
    pastor_contact_phone,
    legal_acceptance_id,
    application_status,
    applicant_note
  ) values (
    v_user_id,
    p_church_name,
    p_location_name,
    p_address,
    p_parish,
    p_denomination_id,
    p_custom_denomination,
    p_pastor_full_name,
    p_pastor_contact_email,
    p_pastor_contact_phone,
    p_legal_acceptance,
    'submitted',
    p_applicant_note
  ) returning id into v_church_id;

end;
$$;
grant execute on function public.submit_church_registration(text, text, text, text, uuid, text, text, text, text, uuid, text) to authenticated;

-- 4. Update Developer portal RPCs to include new fields
create or replace function public.developer_list_churches(
  p_status text default 'all'
)
returns jsonb
language plpgsql
security definer
as $$
declare
  dev public.developer_accounts;
  result jsonb;
begin
  select * into dev from public.require_developer(null);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', crr.id,
      'church_name', crr.church_name,
      'location_name', crr.location_name,
      'parish', crr.parish,
      'address', crr.address,
      'denomination', coalesce(d.display_name, crr.custom_denomination, 'Unknown'),
      'pastor_name', crr.pastor_full_name,
      'pastor_email', crr.pastor_contact_email,
      'applicant_note', crr.applicant_note,
      'status', crr.application_status,
      'created_at', crr.created_at,
      'updated_at', crr.updated_at
    ) order by crr.created_at desc
  ), '[]'::jsonb) into result
  from public.church_registration_requests crr
  left join public.denominations d on d.id = crr.denomination_id
  where (p_status = 'all' or crr.application_status = p_status);

  return result;
end;
$$;
grant execute on function public.developer_list_churches(text) to authenticated;

-- Ensure super_developer can still do approvals, but limit read-only roles
create or replace function public.developer_approve_church(
  p_request_id uuid,
  p_admin_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  dev public.developer_accounts;
  v_church_id uuid;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  if not exists (select 1 from public.church_registration_requests where id = p_request_id and application_status in ('submitted', 'under_review', 'needs_information')) then
    raise exception 'Invalid or non-pending request.';
  end if;

  update public.church_registration_requests
  set application_status = 'approved',
      updated_at = now()
  where id = p_request_id;

  -- Create the real church
  insert into public.churches (name, address, parish, denomination_id)
  select church_name, address, parish, denomination_id
  from public.church_registration_requests
  where id = p_request_id
  returning id into v_church_id;

  -- Grant admin role
  insert into public.church_member_roles (church_id, user_id, role)
  values (v_church_id, p_admin_user_id, 'admin');

  perform public.log_developer_action('approve_church', p_request_id, jsonb_build_object('created_church_id', v_church_id));

  return jsonb_build_object('success', true, 'church_id', v_church_id);
end;
$$;
grant execute on function public.developer_approve_church(uuid, uuid) to authenticated;
