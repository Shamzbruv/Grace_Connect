-- Self-service cancellation for web subscriptions.
--
-- Fygaro has no hosted customer portal to hand a church off to the way Stripe
-- does, so the "manage my subscription" page on the public website has to be
-- the portal. That makes cancelling something this database performs, not
-- something it merely records after the processor did it.
--
-- Cancelling never revokes access immediately. The church paid through the
-- end of the current period, so the subscription stays active and simply
-- stops renewing -- cancellation_effective_at is when it actually lapses.

-- billing_portal_enabled was written as "true" by the webhook on the
-- assumption a processor-hosted portal would exist. With Fygaro it does not,
-- and leaving it true would have the manage page offer a handoff that goes
-- nowhere. It stays in the schema for a future processor that has one, but
-- nothing sets it true today.
update public.church_subscriptions
set billing_portal_enabled = false
where billing_portal_enabled = true;

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

  select * into v_subscription
  from public.church_subscriptions s
  where s.church_id = v_church_id
  limit 1;

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
    coalesce(nullif(trim(coalesce(u.name, '')), ''), 'Church leader'),
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

-- Replaces the version shipped an hour earlier: 'portalAvailable' promised a
-- processor-hosted portal that Fygaro does not provide. What the page
-- actually needs to know is whether cancelling can be done online at all.
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
  where s.church_id = v_church_id
  limit 1;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where cm.church_id = v_church_id
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

revoke all on function public.request_web_subscription_cancellation_internal(uuid, text)
  from public, anon, authenticated;
grant execute on function public.request_web_subscription_cancellation_internal(uuid, text)
  to service_role;
