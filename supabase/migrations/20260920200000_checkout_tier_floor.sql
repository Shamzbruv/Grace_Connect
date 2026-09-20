-- Stops a church from paying for a smaller plan than it actually uses.
--
-- The first version of this function trusted the tier code the website sent.
-- The website only ever sends the tier calculated from the church's active
-- member count, but the edge function is reachable by anyone who can sign in
-- as a church leader, and nothing stopped a 900-member church asking to be
-- charged the 0-50 price. The amount is signed server-side, so that request
-- would have produced a perfectly valid payment for the wrong money.
--
-- A church may still deliberately pay for a larger plan than it needs -- that
-- costs them more, not less, and is a reasonable thing to want when growth is
-- expected.

create or replace function public.start_web_checkout_session_internal(
  p_actor_id uuid,
  p_tier_code text,
  p_currency text,
  p_provider text,
  p_return_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_church_id text;
  v_tier jsonb;
  v_required_tier jsonb;
  v_required_amount integer;
  v_amount_major integer;
  v_amount_minor bigint;
  v_currency text := upper(nullif(trim(coalesce(p_currency, '')), ''));
  v_provider text := lower(nullif(trim(coalesce(p_provider, '')), ''));
  v_session public.church_checkout_sessions;
  v_church_name text;
  v_member_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if v_currency not in ('USD', 'JMD') then
    raise exception 'Unsupported currency';
  end if;
  if v_provider is null then
    raise exception 'A payment provider is required';
  end if;

  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  v_tier := public.church_subscription_tier_for_code(p_tier_code);
  if v_tier is null or v_tier = 'null'::jsonb then
    raise exception 'Unknown subscription tier';
  end if;
  if coalesce((v_tier->>'customQuote')::boolean, false) then
    raise exception 'This plan is quoted individually and cannot be paid online';
  end if;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where cm.church_id = v_church_id
    and cm.membership_status = 'active';

  v_required_tier := public.church_subscription_tier_for_members(v_member_count);
  if coalesce((v_required_tier->>'customQuote')::boolean, false) then
    raise exception 'This church needs an enterprise quote and cannot be paid online';
  end if;

  v_amount_major := case v_currency
    when 'USD' then (v_tier->>'monthlyUsd')::integer
    else (v_tier->>'monthlyJmd')::integer
  end;
  v_required_amount := case v_currency
    when 'USD' then (v_required_tier->>'monthlyUsd')::integer
    else (v_required_tier->>'monthlyJmd')::integer
  end;

  if v_amount_major is null or v_amount_major <= 0 then
    raise exception 'This plan has no published price in %', v_currency;
  end if;
  if v_required_amount is not null and v_amount_major < v_required_amount then
    raise exception
      'This church has % active members and needs the % plan or larger',
      v_member_count, v_required_tier->>'label';
  end if;

  v_amount_minor := v_amount_major::bigint * 100;

  select c.name into v_church_name
  from public.churches c
  where c.id::text = v_church_id
     or c."placeId"::text = v_church_id
  limit 1;

  insert into public.church_checkout_sessions (
    church_id, requested_by, provider, tier_code, currency,
    amount_minor, return_url, metadata
  )
  values (
    v_church_id, p_actor_id, v_provider, v_tier->>'tierCode', v_currency,
    v_amount_minor, nullif(trim(coalesce(p_return_url, '')), ''),
    jsonb_build_object(
      'memberCountSnapshot', v_member_count,
      'requiredTierCode', v_required_tier->>'tierCode'
    )
  )
  returning * into v_session;

  return jsonb_build_object(
    'sessionId', v_session.id,
    'churchId', v_church_id,
    'churchName', v_church_name,
    'tier', v_tier,
    'requiredTier', v_required_tier,
    'currency', v_currency,
    'amountMinor', v_amount_minor,
    'memberCountSnapshot', v_member_count,
    'providerCustomerId', (
      select s.provider_customer_id
      from public.church_subscriptions s
      where s.church_id = v_church_id
      limit 1
    )
  );
end;
$$;

revoke all on function public.start_web_checkout_session_internal(uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.start_web_checkout_session_internal(uuid, text, text, text, text)
  to service_role;
