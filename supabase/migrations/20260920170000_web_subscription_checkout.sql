-- Web subscription checkout and self-service management.
--
-- Until now a church could only *request* a subscription: every path here
-- (developer_manual, external_invoice, google_play) is settled by a human on
-- the finance side, which is why church_subscriptions_no_automatic_billing_check
-- forbade auto-renewal outright. Paying on the public website introduces the
-- first path where a subscription genuinely renews on its own, so the schema
-- has to admit that -- but only for that path. Every other source keeps the
-- old guarantee exactly as it was.
--
-- Provider columns are deliberately generic (provider/provider_customer_id/
-- provider_subscription_id) rather than named after one processor, the way
-- google_purchase_token is. Which processor settles the money is a commercial
-- decision that can change; the churches, amounts, and periods recorded here
-- should not have to be migrated when it does.

alter table public.church_subscriptions
  add column if not exists provider text,
  add column if not exists provider_customer_id text,
  add column if not exists provider_subscription_id text,
  add column if not exists provider_price_id text,
  add column if not exists provider_status text,
  add column if not exists billing_currency text,
  add column if not exists billing_portal_enabled boolean not null default false;

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_source_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_source_check check (
    source in (
      'developer_manual',
      'external_invoice',
      'google_play',
      'web_checkout',
      'system'
    )
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_provider_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_provider_check check (
    provider is null or char_length(provider) between 2 and 40
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_billing_currency_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_billing_currency_check check (
    billing_currency is null or billing_currency in ('USD', 'JMD')
  );

-- Auto-renewal is now legal, but only for a subscription the church actually
-- bought on the web. A developer grant or an invoice that silently started
-- charging would be exactly the surprise the original constraint existed to
-- prevent.
alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_no_automatic_billing_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_no_automatic_billing_check check (
    source = 'web_checkout'
    or (
      auto_renews = false
      and auto_converts = false
      and next_charge_at is null
    )
  );

create index if not exists church_subscriptions_provider_subscription_idx
  on public.church_subscriptions (provider, provider_subscription_id)
  where provider_subscription_id is not null;

-- Checkout attempts, recorded before the church leaves for the processor.
-- Without this row a payment that completes while the browser is closed has
-- nothing to attach itself to: the webhook knows a processor customer paid,
-- but not which church that was.
create table if not exists public.church_checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  requested_by uuid references auth.users(id) on delete set null,
  provider text not null,
  provider_session_id text,
  provider_customer_id text,
  tier_code text not null,
  currency text not null,
  amount_minor bigint not null,
  status text not null default 'created',
  return_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint church_checkout_sessions_status_check check (
    status in ('created', 'completed', 'expired', 'cancelled', 'failed')
  ),
  constraint church_checkout_sessions_currency_check check (
    currency in ('USD', 'JMD')
  ),
  constraint church_checkout_sessions_amount_check check (amount_minor >= 0)
);

create unique index if not exists church_checkout_sessions_provider_session_idx
  on public.church_checkout_sessions (provider, provider_session_id)
  where provider_session_id is not null;

create index if not exists church_checkout_sessions_church_idx
  on public.church_checkout_sessions (church_id, created_at desc);

-- Processor webhooks retry. Recording the processor's own event id and
-- rejecting a repeat is what keeps a retried "payment succeeded" from
-- extending a church's paid period a second time.
create table if not exists public.church_billing_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  church_id text,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  process_error text,
  constraint church_billing_events_provider_event_unique
    unique (provider, provider_event_id)
);

create index if not exists church_billing_events_church_idx
  on public.church_billing_events (church_id, received_at desc);

alter table public.church_checkout_sessions enable row level security;
alter table public.church_billing_events enable row level security;

-- No policies on purpose: both tables are written by edge functions holding
-- the service role and read back through the RPCs below, which re-check the
-- caller. A church leader reading raw processor payloads has no use for them
-- and every reason not to see another church's.

-- Locals below are all v_-prefixed. PL/pgSQL defaults to
-- variable_conflict = error, so a local named `provider` or `currency` would
-- abort at runtime the moment it appeared in a statement touching a table
-- that has a column by that name.

-- ---------------------------------------------------------------------------
-- Checkout start
-- ---------------------------------------------------------------------------

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

  -- Reuses the same leader check the request form already enforces, so the
  -- ability to start a payment never outruns the ability to ask for one.
  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  v_tier := public.church_subscription_tier_for_code(p_tier_code);
  if v_tier is null or v_tier = 'null'::jsonb then
    raise exception 'Unknown subscription tier';
  end if;
  if coalesce((v_tier->>'customQuote')::boolean, false) then
    -- An enterprise plan has no published price, so there is nothing honest
    -- to charge. Those churches go through the quote form instead.
    raise exception 'This plan is quoted individually and cannot be paid online';
  end if;

  v_amount_major := case v_currency
    when 'USD' then (v_tier->>'monthlyUsd')::integer
    else (v_tier->>'monthlyJmd')::integer
  end;
  if v_amount_major is null or v_amount_major <= 0 then
    raise exception 'This plan has no published price in %', v_currency;
  end if;
  v_amount_minor := v_amount_major::bigint * 100;

  select c.name into v_church_name
  from public.churches c
  where c.id::text = v_church_id
     or c."placeId"::text = v_church_id
  limit 1;

  select count(*)::integer into v_member_count
  from public.church_memberships cm
  where cm.church_id = v_church_id
    and cm.membership_status = 'active';

  insert into public.church_checkout_sessions (
    church_id, requested_by, provider, tier_code, currency,
    amount_minor, return_url, metadata
  )
  values (
    v_church_id, p_actor_id, v_provider, v_tier->>'tierCode', v_currency,
    v_amount_minor, nullif(trim(coalesce(p_return_url, '')), ''),
    jsonb_build_object('memberCountSnapshot', v_member_count)
  )
  returning * into v_session;

  return jsonb_build_object(
    'sessionId', v_session.id,
    'churchId', v_church_id,
    'churchName', v_church_name,
    'tier', v_tier,
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

create or replace function public.attach_web_checkout_session_internal(
  p_session_id uuid,
  p_provider_session_id text,
  p_provider_customer_id text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  update public.church_checkout_sessions cs
  set provider_session_id =
        nullif(trim(coalesce(p_provider_session_id, '')), ''),
      provider_customer_id = coalesce(
        nullif(trim(coalesce(p_provider_customer_id, '')), ''),
        cs.provider_customer_id
      )
  where cs.id = p_session_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Webhook application
-- ---------------------------------------------------------------------------

create or replace function public.apply_web_subscription_event_internal(
  p_provider text,
  p_provider_event_id text,
  p_event_type text,
  p_provider_session_id text default null,
  p_provider_subscription_id text default null,
  p_provider_customer_id text default null,
  p_provider_status text default null,
  p_currency text default null,
  p_amount_minor bigint default null,
  p_current_period_start timestamptz default null,
  p_current_period_end timestamptz default null,
  p_cancel_at timestamptz default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_provider text := lower(nullif(trim(coalesce(p_provider, '')), ''));
  v_event_id text := nullif(trim(coalesce(p_provider_event_id, '')), '');
  v_session_id text := nullif(trim(coalesce(p_provider_session_id, '')), '');
  v_sub_id text := nullif(trim(coalesce(p_provider_subscription_id, '')), '');
  v_customer_id text := nullif(trim(coalesce(p_provider_customer_id, '')), '');
  v_currency text := upper(nullif(trim(coalesce(p_currency, '')), ''));
  v_church_id text;
  v_billing_event_id uuid;
  v_tier_code text;
  v_status text;
  v_billing_state text;
  v_renews boolean;
  v_previous_period_start timestamptz;
  v_subscription public.church_subscriptions;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if v_provider is null or v_event_id is null then
    raise exception 'A provider event id is required';
  end if;

  -- Processors retry webhooks. Claiming the event id first means a retry of
  -- "payment succeeded" loses the race and returns early, instead of pushing
  -- the paid-through date out by a second month.
  insert into public.church_billing_events (
    provider, provider_event_id, event_type, payload
  )
  values (
    v_provider,
    v_event_id,
    coalesce(nullif(trim(coalesce(p_event_type, '')), ''), 'unknown'),
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (provider, provider_event_id) do nothing
  returning id into v_billing_event_id;

  if v_billing_event_id is null then
    return jsonb_build_object('duplicate', true);
  end if;

  -- Resolve the church from whichever handle this event carries. The
  -- subscription id is the durable one; a checkout session only exists for
  -- the first payment, and the customer id is the last resort.
  if v_sub_id is not null then
    select s.church_id into v_church_id
    from public.church_subscriptions s
    where s.provider = v_provider
      and s.provider_subscription_id = v_sub_id
    limit 1;
  end if;

  if v_church_id is null and v_session_id is not null then
    select cs.church_id, cs.tier_code into v_church_id, v_tier_code
    from public.church_checkout_sessions cs
    where cs.provider = v_provider
      and cs.provider_session_id = v_session_id
    limit 1;
  end if;

  if v_church_id is null and v_customer_id is not null then
    select s.church_id into v_church_id
    from public.church_subscriptions s
    where s.provider = v_provider
      and s.provider_customer_id = v_customer_id
    limit 1;
  end if;

  if v_church_id is null then
    update public.church_billing_events
    set processed_at = now(),
        process_error = 'No church matched this event'
    where id = v_billing_event_id;
    return jsonb_build_object('matched', false);
  end if;

  if v_tier_code is null then
    select cs.tier_code into v_tier_code
    from public.church_checkout_sessions cs
    where cs.church_id = v_church_id
    order by cs.created_at desc
    limit 1;
  end if;

  select s.current_period_start into v_previous_period_start
  from public.church_subscriptions s
  where s.church_id = v_church_id
  limit 1;

  v_status := case lower(coalesce(p_provider_status, ''))
    when 'active' then 'active'
    when 'trialing' then 'trialing'
    when 'past_due' then 'past_due'
    when 'unpaid' then 'past_due'
    when 'canceled' then 'cancelled'
    when 'cancelled' then 'cancelled'
    when 'incomplete_expired' then 'inactive'
    else null
  end;

  v_billing_state := case v_status
    when 'active' then 'paid'
    when 'trialing' then 'paid'
    when 'past_due' then 'past_due'
    when 'cancelled' then 'cancelled'
    else null
  end;

  -- A subscription that is ending still serves until its paid-through date,
  -- so it counts as renewing only while no cancellation is pending.
  v_renews := coalesce(v_status in ('active', 'trialing'), false)
    and p_cancel_at is null;

  insert into public.church_subscriptions as target (
    church_id, status, plan_code, source, billing_state, provider,
    provider_subscription_id, provider_customer_id, provider_status,
    billing_currency, billing_portal_enabled, auto_renews,
    current_period_start, current_period_end, next_charge_at,
    cancellation_effective_at, monthly_usd, monthly_jmd, updated_at
  )
  values (
    v_church_id,
    coalesce(v_status, 'inactive'),
    coalesce(v_tier_code, 'manual_free'),
    'web_checkout',
    coalesce(v_billing_state, 'not_configured'),
    v_provider,
    v_sub_id,
    v_customer_id,
    nullif(trim(coalesce(p_provider_status, '')), ''),
    v_currency,
    true,
    v_renews,
    p_current_period_start,
    p_current_period_end,
    case when v_renews then p_current_period_end else null end,
    p_cancel_at,
    case when v_currency = 'USD' then (p_amount_minor / 100)::integer end,
    case when v_currency = 'JMD' then (p_amount_minor / 100)::integer end,
    now()
  )
  on conflict (church_id) do update
  set status = coalesce(v_status, target.status),
      plan_code = coalesce(v_tier_code, target.plan_code),
      source = 'web_checkout',
      billing_state = coalesce(v_billing_state, target.billing_state),
      provider = v_provider,
      provider_subscription_id =
        coalesce(v_sub_id, target.provider_subscription_id),
      provider_customer_id =
        coalesce(v_customer_id, target.provider_customer_id),
      provider_status = coalesce(
        nullif(trim(coalesce(p_provider_status, '')), ''),
        target.provider_status
      ),
      billing_currency = coalesce(v_currency, target.billing_currency),
      billing_portal_enabled = true,
      auto_renews = v_renews,
      current_period_start =
        coalesce(p_current_period_start, target.current_period_start),
      current_period_end =
        coalesce(p_current_period_end, target.current_period_end),
      next_charge_at =
        case when v_renews then p_current_period_end else null end,
      cancellation_effective_at = p_cancel_at,
      monthly_usd = case
        when v_currency = 'USD' then (p_amount_minor / 100)::integer
        else target.monthly_usd
      end,
      monthly_jmd = case
        when v_currency = 'JMD' then (p_amount_minor / 100)::integer
        else target.monthly_jmd
      end,
      updated_at = now()
  returning * into v_subscription;

  if v_session_id is not null then
    update public.church_checkout_sessions cs
    set status = 'completed',
        completed_at = now(),
        provider_customer_id =
          coalesce(v_customer_id, cs.provider_customer_id)
    where cs.provider = v_provider
      and cs.provider_session_id = v_session_id
      and cs.status = 'created';
  end if;

  insert into public.church_subscription_events (
    church_id, subscription_id, event_type, status, plan_code,
    monthly_usd, monthly_jmd, period_end, notes, metadata
  )
  values (
    v_church_id,
    v_subscription.id,
    case
      when v_status = 'cancelled' then 'cancelled'
      when v_status = 'past_due' then 'marked_past_due'
      when coalesce(p_event_type, '') ilike '%payment%' then 'payment_received'
      when v_previous_period_start is not null
        and v_previous_period_start is distinct from p_current_period_start
        then 'renewed'
      else 'activated'
    end,
    v_subscription.status,
    v_subscription.plan_code,
    v_subscription.monthly_usd,
    v_subscription.monthly_jmd,
    p_current_period_end,
    format('%s webhook: %s', v_provider, coalesce(p_event_type, 'event')),
    jsonb_build_object(
      'provider', v_provider,
      'providerEventId', v_event_id
    )
  );

  update public.church_billing_events
  set processed_at = now(), church_id = v_church_id
  where id = v_billing_event_id;

  return jsonb_build_object(
    'matched', true,
    'churchId', v_church_id,
    'status', v_subscription.status
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Self-service portal context
-- ---------------------------------------------------------------------------

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

  return jsonb_build_object(
    'churchId', v_church_id,
    'churchName', v_church_name,
    'memberCount', v_member_count,
    'calculatedTier', public.church_subscription_tier_for_members(v_member_count),
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
        -- The page needs to know whether "Manage billing" can hand off to the
        -- processor's own portal, or whether cancelling still has to go
        -- through the finance team as a request.
        'portalAvailable',
          coalesce(v_subscription.billing_portal_enabled, false)
          and v_subscription.provider_customer_id is not null
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

create or replace function public.get_web_subscription_portal_customer_internal(
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_church_id text;
  v_subscription public.church_subscriptions;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  v_church_id := public.web_subscription_leader_church_id(p_actor_id);

  select * into v_subscription
  from public.church_subscriptions s
  where s.church_id = v_church_id
  limit 1;

  if v_subscription.provider_customer_id is null then
    raise exception 'This church has no online billing account yet';
  end if;

  return jsonb_build_object(
    'churchId', v_church_id,
    'provider', v_subscription.provider,
    'providerCustomerId', v_subscription.provider_customer_id,
    'providerSubscriptionId', v_subscription.provider_subscription_id
  );
end;
$$;

revoke all on function public.start_web_checkout_session_internal(uuid, text, text, text, text)
  from public, anon, authenticated;
revoke all on function public.attach_web_checkout_session_internal(uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.apply_web_subscription_event_internal(
  text, text, text, text, text, text, text, text, bigint,
  timestamptz, timestamptz, timestamptz, jsonb
) from public, anon, authenticated;
revoke all on function public.get_web_subscription_portal_context_internal(uuid)
  from public, anon, authenticated;
revoke all on function public.get_web_subscription_portal_customer_internal(uuid)
  from public, anon, authenticated;

grant execute on function public.start_web_checkout_session_internal(uuid, text, text, text, text)
  to service_role;
grant execute on function public.attach_web_checkout_session_internal(uuid, text, text)
  to service_role;
grant execute on function public.apply_web_subscription_event_internal(
  text, text, text, text, text, text, text, text, bigint,
  timestamptz, timestamptz, timestamptz, jsonb
) to service_role;
grant execute on function public.get_web_subscription_portal_context_internal(uuid)
  to service_role;
grant execute on function public.get_web_subscription_portal_customer_internal(uuid)
  to service_role;
