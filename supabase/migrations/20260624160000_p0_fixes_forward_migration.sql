-- Forward migration for P0 fixes

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
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  inserted_id uuid;
  denom_code text;
  final_church_name text := trim(church_name);
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

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

  if denomination is not null then
    select code into denom_code from public.denominations where id = denomination;
    if denom_code = 'ntcog' then
      if nullif(trim(coalesce(location, '')), '') is not null then
        final_church_name := trim(location) || ' NTCOG';
      else
        final_church_name := trim(regexp_replace(final_church_name, '(?i)\s*(new testament church of god|ntcog)\s*', '', 'g')) || ' NTCOG';
      end if;
    end if;
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

create or replace function public.request_church_membership(
  target_church_id text,
  request_note text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  clean_church_id text := nullif(trim(target_church_id), '');
  inserted_id uuid;
  church_name text;
  leader record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

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

create or replace function public.check_church_registration_conflicts(
  church_name text,
  location_name text default null,
  address text default null,
  parish text default null,
  denomination_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  normalized_name text := lower(regexp_replace(coalesce(church_name, ''), '[^a-z0-9]+', '', 'g'));
  normalized_location text := lower(regexp_replace(coalesce(location_name, ''), '[^a-z0-9]+', '', 'g'));
  normalized_address text := lower(regexp_replace(coalesce(address, ''), '[^a-z0-9]+', '', 'g'));
  match_count integer;
  safe_matches jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', coalesce(nullif(c.display_name, ''), nullif(c.name, ''), 'Possible match'),
    'address', c.address,
    'parish', c.parish,
    'status', case when c.church_status = 'approved' then 'registered' else 'under_review' end
  )), '[]'::jsonb)
    into safe_matches
    from (
      select c.*,
      case
        when lower(regexp_replace(coalesce(c.display_name, c.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name and nullif(parish, '') is not null and lower(coalesce(c.parish, '')) = lower(parish) then 100
        when lower(regexp_replace(coalesce(c.display_name, c.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name and nullif(normalized_address, '') is not null and lower(regexp_replace(coalesce(c.address, ''), '[^a-z0-9]+', '', 'g')) = normalized_address then 100
        when normalized_location <> '' and lower(regexp_replace(coalesce(c.location_name, ''), '[^a-z0-9]+', '', 'g')) = normalized_location and c.denomination_id::text = denomination_id and nullif(parish, '') is not null and lower(coalesce(c.parish, '')) = lower(parish) then 100
        when lower(regexp_replace(coalesce(c.display_name, c.name, ''), '[^a-z0-9]+', '', 'g')) like '%' || normalized_name || '%' and nullif(parish, '') is not null and lower(coalesce(c.parish, '')) = lower(parish) then 50
        when normalized_address <> '' and lower(regexp_replace(coalesce(c.address, ''), '[^a-z0-9]+', '', 'g')) like '%' || normalized_address || '%' and c.denomination_id::text = denomination_id then 50
        else 0
      end as match_score
      from public.churches c
      where normalized_name <> ''
    ) c
    where c.match_score >= 50
    order by c.match_score desc, c."createdAt" desc nulls last
    limit 5;

  match_count := jsonb_array_length(safe_matches);

  return jsonb_build_object(
    'has_conflict', match_count > 0,
    'match_count', match_count,
    'safe_message', case
      when match_count > 0 then 'This church may already be registered on Grace Connect.'
      else 'No likely registration conflict found.'
    end,
    'matches', safe_matches
  );
end;
$$;

create or replace function public.developer_approve_member_request(
  p_user_id uuid,
  p_reason text,
  p_emergency_override boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
  church_name text;
  leader record;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  if not p_emergency_override then
    raise exception 'Emergency override flag is required to approve member requests.';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'A typed reason is required for emergency override.';
  end if;

  select *
    into target
  from public.church_memberships
  where id = p_user_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found';
  end if;

  update public.church_memberships
     set membership_status = 'active',
         reviewed_by = dev.user_id,
         reviewed_at = now(),
         decision_reason = 'Platform Override: ' || trim(p_reason)
   where id = target.id;

  update public.church_memberships
     set membership_status = 'cancelled',
         decision_reason = 'Cancelled because another church membership was approved.'
   where user_id = target.user_id
     and id <> target.id
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
         roles = case when roles is null or array_length(roles, 1) is null then array['Member'] else roles end
   where id = target.user_id;

  for leader in
    select cm.user_id as id
    from public.church_memberships cm
    join public.church_member_roles cmr on cmr.membership_id = cm.id
    where cm.church_id = target.church_id
      and cm.membership_status = 'active'
      and cmr.revoked_at is null
      and public.normalize_role_name(cmr.role_name) in (
        'pastor', 'senior_pastor', 'assistant_pastor', 'acting_pastor',
        'church_admin', 'admin', 'administrator', 'secretary', 'church_secretary'
      )
  loop
    begin
      perform public.create_notification(
        leader.id,
        dev.user_id,
        'membership_approved_override',
        'Membership Emergency Override',
        'A membership request was approved by platform support: ' || trim(p_reason),
        target.church_id,
        'church_memberships',
        target.id::text,
        '/members'
      );
    exception when undefined_function then
      null;
    end;
  end loop;

  perform public.log_developer_action('member_request_approved_override', 'church_membership', target.id::text, jsonb_build_object('userId', target.user_id, 'churchId', target.church_id, 'reason', trim(p_reason)));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_list_churches(
  p_status text default null,
  p_search text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        crr.id::text as id,
        crr.id::text as request_id,
        null::text as "placeId",
        'registration_request'::text as record_type,
        crr.church_name_submitted as name,
        crr.address,
        coalesce(d.display_name, crr.custom_denomination_name) as denomination,
        crr.location_name,
        crr.pastor_name as pastor_or_admin_name,
        case when dev.developer_role in ('super_developer', 'security_admin') then crr.pastor_email
             when crr.pastor_email is not null and position('@' in crr.pastor_email) > 0 then substr(crr.pastor_email, 1, 3) || '***@' || split_part(crr.pastor_email, '@', 2)
             else crr.pastor_email end as pastor_or_admin_email,
        case when dev.developer_role in ('super_developer', 'security_admin') then crr.pastor_phone
             when crr.pastor_phone is not null and length(crr.pastor_phone) >= 4 then '***-***-' || right(crr.pastor_phone, 4)
             else crr.pastor_phone end as pastor_or_admin_phone,
        crr.requested_by_user_id::text as "ownerUserId",
        crr.application_status as status,
        crr.application_status as approval_status,
        false as public_visibility,
        null::timestamptz as approved_at,
        crr.reviewed_at as rejected_at,
        crr.review_notes as rejection_reason,
        null::timestamptz as suspended_at,
        null::text as suspension_reason,
        crr.created_at as "createdAt",
        0::bigint as member_count
      from public.church_registration_requests crr
      left join public.denominations d on d.id = crr.denomination_id
      where crr.application_status in ('submitted', 'under_review', 'needs_information', 'rejected')
        and (
          nullif(trim(coalesce(p_status, '')), '') is null
          or lower(crr.application_status) = lower(p_status)
          or (lower(p_status) = 'pending' and crr.application_status in ('submitted', 'under_review', 'needs_information'))
        )
        and (
          nullif(trim(coalesce(p_search, '')), '') is null
          or crr.church_name_submitted ilike '%' || trim(p_search) || '%'
          or coalesce(crr.address, '') ilike '%' || trim(p_search) || '%'
          or coalesce(crr.pastor_email, '') ilike '%' || trim(p_search) || '%'
        )
      union all
      select
        c.id::text as id,
        null::text as request_id,
        c."placeId"::text as "placeId",
        'church'::text as record_type,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId", c.id) as name,
        c.address,
        coalesce(c.denomination_label, c.denomination) as denomination,
        c.location_name,
        null::text as pastor_or_admin_name,
        null::text as pastor_or_admin_email,
        null::text as pastor_or_admin_phone,
        coalesce(c."ownerUserId", c.owner_user_id::text) as "ownerUserId",
        c.church_status as status,
        c.church_status as approval_status,
        c.public_visibility,
        c.approved_at,
        null::timestamptz as rejected_at,
        null::text as rejection_reason,
        null::timestamptz as suspended_at,
        null::text as suspension_reason,
        c."createdAt",
        (select count(*) from public.church_memberships cm where cm.church_id in (c.id, c."placeId") and cm.membership_status = 'active') as member_count
      from public.churches c
      where (
          nullif(trim(coalesce(p_status, '')), '') is null
          or lower(c.church_status) = lower(p_status)
          or (lower(p_status) = 'approved' and c.church_status = 'approved')
        )
        and (
          nullif(trim(coalesce(p_search, '')), '') is null
          or coalesce(c.display_name, c.name, '') ilike '%' || trim(p_search) || '%'
          or coalesce(c.address, '') ilike '%' || trim(p_search) || '%'
        )
      order by "createdAt" desc nulls last
      limit 200
    ) r
  );
end;
$$;

create or replace function public.developer_list_member_requests(p_search text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        cm.id,
        u.uid,
        u.id as user_id,
        case when dev.developer_role in ('super_developer', 'security_admin') then u.email
             when u.email is not null and position('@' in u.email) > 0 then substr(u.email, 1, 3) || '***@' || split_part(u.email, '@', 2)
             else u.email end as email,
        u."fullName",
        case when dev.developer_role in ('super_developer', 'security_admin') then u.phone
             when u.phone is not null and length(u.phone) >= 4 then '***-***-' || right(u.phone, 4)
             else u.phone end as phone,
        cm.church_id as "placeId",
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id) as "placeName",
        u.roles,
        u."accountState",
        cm.membership_status as "approvalStatus",
        cm.requested_at as "joinDate",
        cm.request_message,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id) as church_name
      from public.church_memberships cm
      join public.users u on u.id = cm.user_id
      left join public.churches c on c.id = cm.church_id or c."placeId" = cm.church_id
      where cm.membership_status = 'pending'
        and (
          nullif(trim(coalesce(p_search, '')), '') is null
          or coalesce(u."fullName", '') ilike '%' || trim(p_search) || '%'
          or coalesce(u.email, '') ilike '%' || trim(p_search) || '%'
          or coalesce(c.display_name, c.name, '') ilike '%' || trim(p_search) || '%'
        )
      order by cm.requested_at desc nulls last
      limit 200
    ) r
  );
end;
$$;

create or replace function public.developer_search_users(
  p_search text default null,
  p_church_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        u.id,
        u.uid,
        case when dev.developer_role in ('super_developer', 'security_admin') then u.email
             when u.email is not null and position('@' in u.email) > 0 then substr(u.email, 1, 3) || '***@' || split_part(u.email, '@', 2)
             else u.email end as email,
        u."fullName",
        case when dev.developer_role in ('super_developer', 'security_admin') then u.phone
             when u.phone is not null and length(u.phone) >= 4 then '***-***-' || right(u.phone, 4)
             else u.phone end as phone,
        u."placeId",
        u."placeName",
        u.roles,
        u."accountState",
        coalesce(cm.membership_status, u."accountState") as "approvalStatus",
        u."isDeveloper",
        u."joinDate"
      from public.users u
      left join lateral (
        select membership_status
        from public.church_memberships cm
        where cm.user_id = u.id
        order by cm.updated_at desc nulls last
        limit 1
      ) cm on true
      where (
          nullif(trim(coalesce(p_search, '')), '') is null
          or coalesce(u."fullName", '') ilike '%' || trim(p_search) || '%'
          or coalesce(u.email, '') ilike '%' || trim(p_search) || '%'
          or coalesce(u."placeName", '') ilike '%' || trim(p_search) || '%'
        )
        and (
          nullif(trim(coalesce(p_church_id, '')), '') is null
          or u."placeId" = p_church_id
        )
      order by u."joinDate" desc nulls last
      limit 200
    ) r
  );
end;
$$;


-- Reconcile legacy user_legal_acceptances
do $$
begin
  if exists (select from pg_tables where schemaname = 'public' and tablename = 'user_legal_acceptances') then
    -- Drop duplicate triggers if they exist
    drop trigger if exists on_auth_user_created_legal on auth.users;
    
    -- Migrate existing legacy acceptances
    insert into public.policy_acceptances (user_id, document_key, document_version, accepted_at, acceptance_source, metadata)
    select user_id, 'terms', coalesce(document_version, 'legacy'), coalesce(accepted_at, now()), coalesce(acceptance_source, 'legacy_migration'), '{}'::jsonb
    from public.user_legal_acceptances ula
    where not exists (
      select 1 from public.policy_acceptances pa where pa.user_id = ula.user_id and pa.document_key = 'terms'
    );
  end if;
end;
$$;
