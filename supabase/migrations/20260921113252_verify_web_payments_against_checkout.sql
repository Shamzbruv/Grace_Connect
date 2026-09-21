-- Only the checkout's immutable reference and exact price authorize access.
-- A customer email is not a subscription identifier (one leader can pay for
-- multiple churches), and a successful payment is not a recurring mandate.
create or replace function public.apply_web_subscription_event_internal(
  p_provider text, p_provider_event_id text, p_event_type text,
  p_provider_session_id text default null,
  p_provider_subscription_id text default null,
  p_provider_customer_id text default null,
  p_provider_status text default null, p_currency text default null,
  p_amount_minor bigint default null,
  p_current_period_start timestamptz default null,
  p_current_period_end timestamptz default null,
  p_cancel_at timestamptz default null, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_event uuid;
  v_session public.church_checkout_sessions;
  v_subscription public.church_subscriptions;
  v_error text;
  v_start timestamptz;
  v_end timestamptz;
  v_cancellation timestamptz;
  v_church_id text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if p_provider is distinct from 'fygaro' or nullif(btrim(p_provider_event_id),'') is null
     or p_event_type is distinct from 'payment_succeeded' then
    raise exception 'Unsupported payment event' using errcode='22023';
  end if;
  insert into public.church_billing_events(provider,provider_event_id,event_type,payload)
    values(p_provider,p_provider_event_id,p_event_type,jsonb_build_object(
      'transactionId',p_provider_event_id,'customReference',p_provider_session_id,
      'currency',p_currency,'amountMinor',p_amount_minor,'paidAt',p_current_period_start))
    on conflict(provider,provider_event_id) do nothing returning id into v_event;
  if v_event is null then return jsonb_build_object('duplicate',true); end if;

  select * into v_session from public.church_checkout_sessions
    where provider=p_provider and provider_session_id=p_provider_session_id
    for update;
  if v_session.id is null then v_error := 'No checkout matched this event';
  elsif v_session.status <> 'created' then v_error := 'Checkout is already completed or closed';
  elsif p_currency is distinct from v_session.currency
     or p_amount_minor is distinct from v_session.amount_minor then
    v_error := 'Paid amount or currency does not match checkout';
  elsif p_current_period_start is null
     or p_current_period_start < v_session.created_at - interval '5 minutes'
     or p_current_period_start > now() + interval '5 minutes'
     or p_current_period_start > v_session.created_at + interval '1 day' then
    v_error := 'Payment date is outside the checkout window';
  end if;
  if v_error is not null then
    update public.church_billing_events set church_id=v_session.church_id,
      processed_at=now(),process_error=v_error where id=v_event;
    return jsonb_build_object('matched',false,'reason',v_error);
  end if;

  -- Serialize different checkouts for the same church, including first insert.
  select c.id into v_church_id from public.churches c
    where c.id=v_session.church_id or c."placeId"=v_session.church_id limit 1;
  if v_church_id is null then raise exception 'Checkout church no longer exists'; end if;
  perform pg_advisory_xact_lock(hashtextextended('web_billing:'||v_church_id,0));
  select sub.* into v_subscription from public.church_subscriptions sub
    join public.churches c on sub.church_id=c.id or sub.church_id=c."placeId"
    where c.id=v_church_id for update of sub;
  v_church_id := coalesce(v_subscription.church_id,v_church_id);
  -- A second deliberate payment adds its month after existing paid access.
  -- Delayed hooks cannot shorten an already purchased period.
  v_start := greatest(p_current_period_start,coalesce(v_subscription.current_period_end,p_current_period_start));
  v_end := ((v_start at time zone 'UTC') + interval '1 month') at time zone 'UTC';
  v_cancellation := case when v_subscription.cancellation_effective_at is not null
    then greatest(v_subscription.cancellation_effective_at,v_end) else null end;

  if v_subscription.id is not null then
    update public.church_subscriptions set status='active',plan_code=v_session.tier_code,
      source='web_checkout',billing_state='paid',provider=p_provider,
      provider_customer_id=p_provider_customer_id,provider_status='active',
      billing_currency=v_session.currency,billing_portal_enabled=false,
      auto_renews=false,auto_converts=false,next_charge_at=null,
      current_period_start=least(current_period_start,v_start),current_period_end=v_end,
      cancellation_effective_at=v_cancellation,
      monthly_usd=case when v_session.currency='USD' then (v_session.amount_minor/100)::integer end,
      monthly_jmd=case when v_session.currency='JMD' then (v_session.amount_minor/100)::integer end,
      updated_at=now() where id=v_subscription.id returning * into v_subscription;
  else
    insert into public.church_subscriptions (
      church_id,status,plan_code,source,billing_state,provider,
      provider_customer_id,provider_status,billing_currency,billing_portal_enabled,
      auto_renews,auto_converts,current_period_start,current_period_end,next_charge_at,
      cancellation_effective_at,monthly_usd,monthly_jmd,updated_at
    ) values (
      v_church_id,'active',v_session.tier_code,'web_checkout','paid',p_provider,
      p_provider_customer_id,'active',v_session.currency,false,false,false,v_start,v_end,null,
      v_cancellation,
      case when v_session.currency='USD' then (v_session.amount_minor/100)::integer end,
      case when v_session.currency='JMD' then (v_session.amount_minor/100)::integer end,now()
    ) returning * into v_subscription;
  end if;

  update public.church_checkout_sessions set status='completed',completed_at=now(),
    provider_customer_id=p_provider_customer_id where id=v_session.id;
  insert into public.church_subscription_events(
    church_id,subscription_id,event_type,status,plan_code,monthly_usd,monthly_jmd,
    period_end,notes,metadata
  ) values (
    v_session.church_id,v_subscription.id,'payment_received','active',v_session.tier_code,
    v_subscription.monthly_usd,v_subscription.monthly_jmd,v_end,
    'Verified one-month web payment',jsonb_build_object('provider',p_provider,'providerEventId',p_provider_event_id)
  );
  update public.church_billing_events set church_id=v_session.church_id,
    processed_at=now() where id=v_event;
  return jsonb_build_object('matched',true,'churchId',v_session.church_id,
    'status','active','accessUntil',v_end);
end;
$$;
revoke all on function public.apply_web_subscription_event_internal(
  text,text,text,text,text,text,text,text,bigint,timestamptz,timestamptz,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function public.apply_web_subscription_event_internal(
  text,text,text,text,text,text,text,text,bigint,timestamptz,timestamptz,timestamptz,jsonb
) to service_role;

-- Cancellation uses the same lock as payment application.
create or replace function public.request_web_subscription_cancellation_internal(
  p_actor_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_church_id text;
  v_subscription public.church_subscriptions;
  v_effective_at timestamptz;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_contact_name text;
  v_contact_email text;
  v_member_count integer;
  v_request_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  select c.id into v_church_id from public.churches c
    where c.id=v_church_id or c."placeId"=v_church_id limit 1;
  perform pg_advisory_xact_lock(hashtextextended('web_billing:'||v_church_id,0));
  select s.* into v_subscription from public.church_subscriptions s
    join public.churches c on s.church_id=c.id or s.church_id=c."placeId"
    where c.id=v_church_id limit 1 for update of s;
  v_church_id := coalesce(v_subscription.church_id,v_church_id);

  if v_subscription.id is null then
    raise exception 'This church has no subscription to cancel';
  end if;
  if v_subscription.status = 'cancelled' then
    raise exception 'This subscription is already cancelled';
  end if;
  if v_subscription.cancellation_effective_at is not null then
    -- Already scheduled. Returning the existing date is friendlier than an
    -- error, and stops a double tap from moving the date around.
    return jsonb_build_object(
      'alreadyScheduled', true,
      'effectiveAt', v_subscription.cancellation_effective_at
    );
  end if;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where cm.church_id = v_church_id
    and cm.membership_status = 'active';

  select
    coalesce(nullif(trim(coalesce(u."displayName",u."fullName",'')),''),'Church leader'),
    coalesce(nullif(trim(coalesce(u.email, '')), ''), au.email)
  into v_contact_name, v_contact_email
  from auth.users au
  left join public.users u
    on u.id = au.id or u.uid = au.id::text
  where au.id = p_actor_id
  limit 1;

  -- A subscription bought on the web stops renewing here and now. One bought
  -- any other way was never renewing on its own, so the only meaningful act
  -- is telling the finance team -- which the request row below does either
  -- way, because with Fygaro a human still has to stop the recurring
  -- schedule on the processor side.
  v_effective_at := coalesce(
    v_subscription.current_period_end,
    v_subscription.free_until,
    now()
  );

  update public.church_subscriptions s
  set auto_renews = false,
      next_charge_at = null,
      cancellation_effective_at = v_effective_at,
      updated_at = now()
  where s.church_id = v_church_id
  returning * into v_subscription;

  insert into public.church_subscription_requests (
    church_id, requested_by, request_type, requested_tier_code,
    member_count_snapshot, monthly_usd, monthly_jmd,
    contact_name, contact_email, message, status
  )
  values (
    v_church_id, p_actor_id, 'cancellation', null,
    v_member_count, v_subscription.monthly_usd, v_subscription.monthly_jmd,
    coalesce(v_contact_name, 'Church leader'),
    coalesce(v_contact_email, 'unknown@graceconnect.love'),
    coalesce(
      v_reason,
      'Cancellation requested from the subscription management website.'
    ),
    'pending'
  )
  -- One open cancellation per church is enough; the partial unique index
  -- already says so, and a second row would just duplicate the finance task.
  on conflict do nothing
  returning id into v_request_id;

  insert into public.church_subscription_events (
    church_id, subscription_id, request_id, actor_user_id, event_type,
    status, plan_code, member_count_snapshot, monthly_usd, monthly_jmd,
    period_end, notes, metadata
  )
  values (
    v_church_id, v_subscription.id, v_request_id, p_actor_id, 'cancelled',
    v_subscription.status, v_subscription.plan_code, v_member_count,
    v_subscription.monthly_usd, v_subscription.monthly_jmd,
    v_effective_at,
    coalesce(v_reason, 'Cancellation scheduled from the website.'),
    jsonb_build_object(
      'source', 'web_manage',
      'effectiveAt', v_effective_at,
      'subscriptionSource', v_subscription.source
    )
  );

  return jsonb_build_object(
    'alreadyScheduled', false,
    'effectiveAt', v_effective_at,
    'requestId', v_request_id,
    'accessUntil', v_effective_at
  );
end;
$$;


-- Normalize after authorization so either church alias resolves one account.
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

  return (select c.id from public.churches c
    where c.id=target_church_id or c."placeId"=target_church_id limit 1);
end;
$$;

create or replace function public.get_web_subscription_portal_context_internal(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_church_id text;
  v_church_name text;
  v_subscription public.church_subscriptions;
  v_member_count integer;
  v_open_cancellation boolean;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  select c.name into v_church_name
  from public.churches c
  where c.id::text = v_church_id
     or c."placeId"::text = v_church_id
  limit 1;

  select * into v_subscription
  from public.church_subscriptions s
  where s.church_id=v_church_id or s.church_id=(select c."placeId" from public.churches c where c.id=v_church_id)
  limit 1;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where (cm.church_id=v_church_id or cm.church_id=(select c."placeId" from public.churches c where c.id=v_church_id))
    and cm.membership_status = 'active';

  select exists (
    select 1
    from public.church_subscription_requests r
    where r.church_id = v_church_id
      and r.request_type = 'cancellation'
      and r.status in ('pending', 'in_review', 'quoted')
  ) into v_open_cancellation;

  return jsonb_build_object(
    'churchId', v_church_id,
    'churchName', v_church_name,
    'memberCount', v_member_count,
    'calculatedTier', public.church_subscription_tier_for_members(v_member_count),
    'hasOpenCancellation', v_open_cancellation,
    'subscription', case
      when v_subscription.id is null then null
      else jsonb_build_object(
        'status', v_subscription.status,
        'planCode', v_subscription.plan_code,
        'source', v_subscription.source,
        'billingState', v_subscription.billing_state,
        'billingCurrency', v_subscription.billing_currency,
        'monthlyUsd', v_subscription.monthly_usd,
        'monthlyJmd', v_subscription.monthly_jmd,
        'autoRenews', v_subscription.auto_renews,
        'currentPeriodStart', v_subscription.current_period_start,
        'currentPeriodEnd', v_subscription.current_period_end,
        'nextChargeAt', v_subscription.next_charge_at,
        'cancellationEffectiveAt', v_subscription.cancellation_effective_at,
        'provider', v_subscription.provider,
        'canCancelOnline',
          v_subscription.status <> 'cancelled'
          and v_subscription.cancellation_effective_at is null
      )
    end,
    'recentEvents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'eventType', e.event_type,
        'status', e.status,
        'planCode', e.plan_code,
        'periodEnd', e.period_end,
        'createdAt', e.created_at
      ) order by e.created_at desc)
      from (
        select *
        from public.church_subscription_events
        where church_id = v_church_id
        order by created_at desc
        limit 10
      ) e
    ), '[]'::jsonb)
  );
end;
$$;

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
  if v_currency is null or v_currency not in ('USD', 'JMD') then
    raise exception 'Unsupported currency';
  end if;
  if v_provider is null then
    raise exception 'A payment provider is required';
  end if;

  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  if (select count(*) from public.church_checkout_sessions cs
    where cs.requested_by=p_actor_id and cs.created_at>now()-interval '1 hour') >= 10 then
    raise exception 'Too many checkout requests. Please try again later.' using errcode='54000';
  end if;
  v_tier := public.church_subscription_tier_for_code(p_tier_code);
  if v_tier is null or v_tier = 'null'::jsonb then
    raise exception 'Unknown subscription tier';
  end if;
  if coalesce((v_tier->>'customQuote')::boolean, false) then
    raise exception 'This plan is quoted individually and cannot be paid online';
  end if;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where (cm.church_id=v_church_id or cm.church_id=(select c."placeId" from public.churches c where c.id=v_church_id))
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
