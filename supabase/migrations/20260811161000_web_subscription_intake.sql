-- Authenticated website-only plan and enterprise intake.
--
-- The Play-distributed Android app intentionally has no enrollment or external
-- payment funnel. Browser clients call an origin-restricted Edge Function,
-- which validates the signed-in user and then invokes this service-role-only
-- function. This workflow creates an audited request only: it never activates
-- a subscription, changes access, creates an invoice, or charges anything.

create or replace function public.subscription_request_to_json(
  p_request public.church_subscription_requests
)
returns jsonb
language sql
stable
set search_path to 'public'
as $$
  select jsonb_build_object(
    'id', p_request.id,
    'churchId', p_request.church_id,
    'churchName', coalesce(
      (
        select coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId"::text, c.id::text)
        from public.churches c
        where c.id::text = any(public.subscription_church_ids(p_request.church_id))
           or c."placeId"::text = any(public.subscription_church_ids(p_request.church_id))
        limit 1
      ),
      p_request.church_id
    ),
    'requestType', p_request.request_type,
    'requestedTierCode', p_request.requested_tier_code,
    'memberCountSnapshot', p_request.member_count_snapshot,
    'monthlyUsd', p_request.monthly_usd,
    'monthlyJmd', p_request.monthly_jmd,
    'contactName', p_request.contact_name,
    'contactEmail', p_request.contact_email,
    'contactPhone', p_request.contact_phone,
    'message', p_request.message,
    'status', p_request.status,
    'channel', coalesce(p_request.terms_snapshot ->> 'channel', 'unknown'),
    'requestOnly', lower(coalesce(p_request.terms_snapshot ->> 'requestDoesNotCharge', 'false')) = 'true',
    'developerNotes', p_request.developer_notes,
    'termsVersion', p_request.terms_version,
    'termsLocale', p_request.terms_locale,
    'assignedTo', p_request.assigned_to,
    'createdAt', p_request.created_at,
    'updatedAt', p_request.updated_at,
    'resolvedAt', p_request.resolved_at
  );
$$;

create or replace function public.web_subscription_leader_church_id(
  p_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  target_church_id text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_actor_id is null then
    raise exception 'An authenticated church leader is required';
  end if;

  select cm.church_id
    into target_church_id
  from public.church_memberships cm
  join public.churches c
    on c.id::text = cm.church_id
    or c."placeId"::text = cm.church_id
  where cm.user_id = p_actor_id
    and cm.membership_status = 'active'
    and c.church_status = 'approved'
  order by cm.reviewed_at desc nulls last, cm.created_at desc
  limit 1;

  if target_church_id is null then
    raise exception 'An approved active church membership is required';
  end if;
  if not (
    exists (
      select 1
      from public.church_memberships cm
      join public.church_member_roles cmr
        on cmr.membership_id = cm.id
       and cmr.revoked_at is null
      where cm.user_id = p_actor_id
        and cm.church_id = target_church_id
        and cm.membership_status = 'active'
        and public.normalize_role_name(cmr.role_name) in (
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'church_admin',
          'church_administrator',
          'admin',
          'administrator',
          'treasurer',
          'financial_secretary',
          'finance',
          'finance_officer',
          'accountant'
        )
    )
    or exists (
      select 1
      from public.users u
      where (u.id = p_actor_id or u.uid = p_actor_id::text)
        and (
          'manageChurchSubscription' = any(coalesce(u."appPrivileges", '{}'::text[]))
          or 'manageFinances' = any(coalesce(u."appPrivileges", '{}'::text[]))
        )
    )
  ) then
    raise exception 'Church subscription management permission is required';
  end if;

  return target_church_id;
end;
$$;

create or replace function public.web_subscription_has_current_state(
  p_church_id text
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.church_subscriptions cs
    where cs.church_id = any(public.subscription_church_ids(p_church_id))
      and cs.status not in ('cancelled', 'inactive')
      and (
        cs.status in ('active', 'trialing', 'grace_period', 'past_due')
        or cs.current_period_end >= now()
        or cs.free_until >= now()
        or cs.grace_until >= now()
      )
  );
$$;

create or replace function public.get_web_subscription_request_context_internal(
  p_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  target_church_id text := public.web_subscription_leader_church_id(p_actor_id);
  canonical_church_id text := public.subscription_canonical_church_id(target_church_id);
  member_count integer := public.church_subscription_member_count(target_church_id);
  tier jsonb := public.church_subscription_tier_for_members(member_count);
  has_current boolean := public.web_subscription_has_current_state(target_church_id);
  church_name text;
  subscription_row public.church_subscriptions;
  recommended_intent text;
begin
  select coalesce(nullif(c.display_name, ''), nullif(c.name, ''), canonical_church_id)
    into church_name
  from public.churches c
  where c.id::text = any(public.subscription_church_ids(target_church_id))
     or c."placeId"::text = any(public.subscription_church_ids(target_church_id))
  limit 1;

  select cs.*
    into subscription_row
  from public.church_subscriptions cs
  where cs.church_id = any(public.subscription_church_ids(target_church_id))
  order by cs.updated_at desc
  limit 1;

  recommended_intent := case
    when tier ->> 'tierCode' = 'enterprise_1001_plus' then 'enterprise_quote'
    when has_current then 'change_plan'
    else 'new_subscription'
  end;

  return jsonb_build_object(
    'canManage', true,
    'churchId', canonical_church_id,
    'churchName', coalesce(church_name, canonical_church_id),
    'memberCount', member_count,
    'calculatedTier', tier,
    'recommendedIntent', recommended_intent,
    'hasCurrentSubscription', has_current,
    'subscription', case when subscription_row.id is null then null else jsonb_build_object(
      'status', subscription_row.status,
      'planCode', subscription_row.plan_code,
      'activeUntil', greatest(
        subscription_row.current_period_end,
        subscription_row.free_until,
        subscription_row.grace_until
      )
    ) end,
    'requests', (
      select coalesce(jsonb_agg(
        (public.subscription_request_to_json(r) - 'developerNotes' - 'assignedTo')
        order by r.created_at desc
      ), '[]'::jsonb)
      from (
        select csr.*
        from public.church_subscription_requests csr
        where csr.church_id = any(public.subscription_church_ids(target_church_id))
        order by csr.created_at desc
        limit 12
      ) r
    ),
    'requestOnly', true,
    'charged', false,
    'activated', false,
    'invoiced', false
  );
end;
$$;

revoke all on function public.web_subscription_leader_church_id(uuid)
  from public, anon, authenticated;
revoke all on function public.web_subscription_has_current_state(text)
  from public, anon, authenticated;
revoke all on function public.get_web_subscription_request_context_internal(uuid)
  from public, anon, authenticated;
grant execute on function public.web_subscription_leader_church_id(uuid)
  to service_role;
grant execute on function public.web_subscription_has_current_state(text)
  to service_role;
grant execute on function public.get_web_subscription_request_context_internal(uuid)
  to service_role;

create or replace function public.submit_web_subscription_request_internal(
  p_actor_id uuid,
  p_intent text,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text default null,
  p_message text default null,
  p_terms_accepted boolean default false,
  p_origin text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  target_church_id text;
  canonical_church_id text;
  normalized_intent text := lower(trim(coalesce(p_intent, '')));
  expected_intent text;
  member_count integer;
  tier jsonb;
  tier_code text;
  has_subscription boolean := false;
  request_row public.church_subscription_requests;
  was_created boolean := false;
  was_refreshed boolean := false;
  safe_origin text := left(nullif(trim(coalesce(p_origin, '')), ''), 320);
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  target_church_id := public.web_subscription_leader_church_id(p_actor_id);

  if p_terms_accepted is not true then
    raise exception 'The request-only terms must be accepted';
  end if;
  if nullif(trim(coalesce(p_contact_name, '')), '') is null then
    raise exception 'Contact name is required';
  end if;
  if nullif(trim(coalesce(p_contact_email, '')), '') is null
      or trim(p_contact_email) !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    raise exception 'A valid contact email is required';
  end if;
  if char_length(trim(p_contact_name)) > 160
      or char_length(trim(p_contact_email)) > 320
      or char_length(trim(coalesce(p_contact_phone, ''))) > 64
      or char_length(trim(coalesce(p_message, ''))) > 4000 then
    raise exception 'One or more request fields are too long';
  end if;
  if safe_origin is null or safe_origin !~ '^https?://[^[:space:]]+$' then
    raise exception 'A verified website origin is required';
  end if;

  canonical_church_id := public.subscription_canonical_church_id(target_church_id);
  member_count := public.church_subscription_member_count(target_church_id);
  tier := public.church_subscription_tier_for_members(member_count);
  tier_code := tier ->> 'tierCode';

  has_subscription := public.web_subscription_has_current_state(target_church_id);

  expected_intent := case
    when tier_code = 'enterprise_1001_plus' then 'enterprise_quote'
    when has_subscription then 'change_plan'
    else 'new_subscription'
  end;
  if normalized_intent <> expected_intent then
    raise exception 'The request type no longer matches this church subscription state. Refresh and try again.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'web_subscription_request:' || canonical_church_id || ':' || expected_intent,
      0
    )
  );

  select csr.*
    into request_row
  from public.church_subscription_requests csr
  where csr.church_id = any(public.subscription_church_ids(canonical_church_id))
    and csr.request_type = expected_intent
    and csr.status in ('pending', 'in_review', 'quoted')
  order by csr.created_at desc
  limit 1
  for update;

  -- Double-clicks and rapid retries return the existing request without adding
  -- another audit event. This is an authenticated abuse/idempotency boundary.
  if request_row.id is not null
      and request_row.updated_at > now() - interval '2 minutes' then
    return jsonb_build_object(
      'request', public.subscription_request_to_json(request_row)
        - 'developerNotes'
        - 'assignedTo',
      'created', false,
      'refreshed', false,
      'deduplicated', true,
      'requestOnly', true,
      'charged', false,
      'activated', false,
      'invoiced', false
    );
  end if;

  if request_row.id is null then
    insert into public.church_subscription_requests (
      church_id,
      requested_by,
      request_type,
      requested_tier_code,
      member_count_snapshot,
      monthly_usd,
      monthly_jmd,
      contact_name,
      contact_email,
      contact_phone,
      message,
      terms_version,
      terms_locale,
      terms_snapshot
    ) values (
      canonical_church_id,
      p_actor_id,
      expected_intent,
      tier_code,
      member_count,
      case when (tier ->> 'monthlyUsd') is null then null else (tier ->> 'monthlyUsd')::integer end,
      case when (tier ->> 'monthlyJmd') is null then null else (tier ->> 'monthlyJmd')::integer end,
      trim(p_contact_name),
      lower(trim(p_contact_email)),
      nullif(trim(coalesce(p_contact_phone, '')), ''),
      nullif(trim(coalesce(p_message, '')), ''),
      '2026-08-11-en-v1',
      'en',
      jsonb_build_object(
        'channel', 'web_subscription_intake',
        'origin', safe_origin,
        'billingCycle', 'monthly',
        'requestDoesNotCharge', true,
        'requestDoesNotActivate', true,
        'requestDoesNotInvoice', true,
        'autoRenews', false,
        'autoConverts', false,
        'requiresDeveloperReview', true
      )
    )
    returning * into request_row;
    was_created := true;
  else
    update public.church_subscription_requests
       set requested_by = p_actor_id,
           requested_tier_code = tier_code,
           member_count_snapshot = member_count,
           monthly_usd = case when (tier ->> 'monthlyUsd') is null then null else (tier ->> 'monthlyUsd')::integer end,
           monthly_jmd = case when (tier ->> 'monthlyJmd') is null then null else (tier ->> 'monthlyJmd')::integer end,
           contact_name = trim(p_contact_name),
           contact_email = lower(trim(p_contact_email)),
           contact_phone = nullif(trim(coalesce(p_contact_phone, '')), ''),
           message = nullif(trim(coalesce(p_message, '')), ''),
           terms_version = '2026-08-11-en-v1',
           terms_locale = 'en',
           terms_snapshot = jsonb_build_object(
             'channel', 'web_subscription_intake',
             'origin', safe_origin,
             'billingCycle', 'monthly',
             'requestDoesNotCharge', true,
             'requestDoesNotActivate', true,
             'requestDoesNotInvoice', true,
             'autoRenews', false,
             'autoConverts', false,
             'requiresDeveloperReview', true
           )
     where id = request_row.id
    returning * into request_row;
    was_refreshed := true;
  end if;

  insert into public.church_subscription_events (
    church_id,
    request_id,
    actor_user_id,
    event_type,
    status,
    plan_code,
    member_count_snapshot,
    monthly_usd,
    monthly_jmd,
    metadata
  ) values (
    canonical_church_id,
    request_row.id,
    p_actor_id,
    case when was_created then 'request_submitted' else 'request_refreshed' end,
    request_row.status,
    tier_code,
    member_count,
    request_row.monthly_usd,
    request_row.monthly_jmd,
    jsonb_build_object(
      'requestType', expected_intent,
      'channel', 'web_subscription_intake',
      'origin', safe_origin,
      'requestOnly', true
    )
  );

  return jsonb_build_object(
    'request', public.subscription_request_to_json(request_row)
      - 'developerNotes'
      - 'assignedTo',
    'created', was_created,
    'refreshed', was_refreshed,
    'deduplicated', false,
    'requestOnly', true,
    'charged', false,
    'activated', false,
    'invoiced', false
  );
end;
$$;

revoke all on function public.submit_web_subscription_request_internal(
  uuid, text, text, text, text, text, boolean, text
) from public, anon, authenticated;
grant execute on function public.submit_web_subscription_request_internal(
  uuid, text, text, text, text, text, boolean, text
) to service_role;
