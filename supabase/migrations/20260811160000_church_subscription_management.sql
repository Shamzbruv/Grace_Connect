-- Church subscription account management and audited platform finance records.
--
-- The Play-distributed Android app is consumption/account-management only: it
-- exposes no purchase, enrollment, payment link, or payment instructions.
-- Existing-plan support/cancellation requests are audited here. Any approved
-- web intake is isolated behind a separate service-role-only server workflow;
-- authorized platform finance developers record subscription state changes.

alter table public.church_subscriptions
  add column if not exists member_count_snapshot integer,
  add column if not exists monthly_usd integer,
  add column if not exists monthly_jmd integer,
  add column if not exists billing_state text not null default 'not_configured',
  add column if not exists billing_reference text,
  add column if not exists last_request_id uuid,
  add column if not exists billing_cycle text not null default 'monthly',
  add column if not exists auto_renews boolean not null default false,
  add column if not exists auto_converts boolean not null default false,
  add column if not exists next_charge_at timestamptz,
  add column if not exists cancellation_effective_at timestamptz,
  add column if not exists terms_version text not null default '2026-08-11-en-v1';

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_source_check;

alter table public.church_subscriptions
  add constraint church_subscriptions_source_check check (
    source in ('developer_manual', 'external_invoice', 'google_play', 'system')
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_billing_state_check;

alter table public.church_subscriptions
  add constraint church_subscriptions_billing_state_check check (
    billing_state in (
      'not_configured',
      'request_pending',
      'quote_pending',
      'invoiced',
      'paid',
      'past_due',
      'cancelled',
      'manual_grant'
    )
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_billing_cycle_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_billing_cycle_check
    check (billing_cycle = 'monthly');

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_no_automatic_billing_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_no_automatic_billing_check check (
    auto_renews = false
    and auto_converts = false
    and next_charge_at is null
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_member_count_check;

alter table public.church_subscriptions
  add constraint church_subscriptions_member_count_check
    check (member_count_snapshot is null or member_count_snapshot >= 0);

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_amounts_check;

alter table public.church_subscriptions
  add constraint church_subscriptions_amounts_check check (
    (monthly_usd is null or monthly_usd >= 0)
    and (monthly_jmd is null or monthly_jmd >= 0)
  );

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_billing_text_length_check;
alter table public.church_subscriptions
  add constraint church_subscriptions_billing_text_length_check check (
    (billing_reference is null or char_length(billing_reference) <= 320)
    and (notes is null or char_length(notes) <= 4000)
  ) not valid;

create table if not exists public.church_subscription_requests (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  requested_by uuid references auth.users(id) on delete set null,
  request_type text not null,
  requested_tier_code text,
  member_count_snapshot integer not null,
  monthly_usd integer,
  monthly_jmd integer,
  contact_name text not null,
  contact_email text not null,
  contact_phone text,
  message text,
  status text not null default 'pending',
  developer_notes text,
  terms_version text not null default '2026-08-11-en-v1',
  terms_locale text not null default 'en',
  terms_snapshot jsonb not null default '{}'::jsonb,
  assigned_to uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint church_subscription_requests_type_check check (
    request_type in (
      'new_subscription',
      'change_plan',
      'enterprise_quote',
      'billing_support',
      'cancellation'
    )
  ),
  constraint church_subscription_requests_tier_check check (
    requested_tier_code is null or requested_tier_code in (
      'tier_0_50',
      'tier_51_100',
      'tier_101_150',
      'tier_151_200',
      'tier_201_300',
      'tier_301_400',
      'tier_401_500',
      'tier_501_700',
      'tier_701_900',
      'tier_901_1000',
      'enterprise_1001_plus'
    )
  ),
  constraint church_subscription_requests_status_check check (
    status in (
      'pending',
      'in_review',
      'quoted',
      'approved',
      'rejected',
      'closed',
      'cancelled'
    )
  ),
  constraint church_subscription_requests_member_count_check
    check (member_count_snapshot >= 0),
  constraint church_subscription_requests_amounts_check check (
    (monthly_usd is null or monthly_usd >= 0)
    and (monthly_jmd is null or monthly_jmd >= 0)
  ),
  constraint church_subscription_requests_text_length_check check (
    char_length(contact_name) between 1 and 160
    and char_length(contact_email) between 3 and 320
    and (contact_phone is null or char_length(contact_phone) <= 64)
    and (message is null or char_length(message) <= 4000)
    and (developer_notes is null or char_length(developer_notes) <= 4000)
    and char_length(terms_version) between 1 and 64
    and char_length(terms_locale) between 2 and 16
  )
);

create index if not exists church_subscription_requests_church_idx
  on public.church_subscription_requests (church_id, created_at desc);

create index if not exists church_subscription_requests_status_idx
  on public.church_subscription_requests (status, created_at desc);

alter table public.church_subscriptions
  drop constraint if exists church_subscriptions_last_request_id_fkey;
alter table public.church_subscriptions
  add constraint church_subscriptions_last_request_id_fkey
    foreign key (last_request_id)
    references public.church_subscription_requests(id)
    on delete set null;

create unique index if not exists church_subscription_requests_one_open_type_idx
  on public.church_subscription_requests (church_id, request_type)
  where status in ('pending', 'in_review', 'quoted');

create table if not exists public.church_subscription_events (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  subscription_id uuid references public.church_subscriptions(id) on delete set null,
  request_id uuid references public.church_subscription_requests(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  status text,
  plan_code text,
  member_count_snapshot integer,
  monthly_usd integer,
  monthly_jmd integer,
  period_end timestamptz,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint church_subscription_events_type_check check (
    event_type in (
      'request_submitted',
      'request_refreshed',
      'request_status_changed',
      'activated',
      'renewed',
      'trial_started',
      'payment_received',
      'marked_past_due',
      'cancelled',
      'note'
    )
  ),
  constraint church_subscription_events_notes_length_check check (
    notes is null or char_length(notes) <= 4000
  )
);

create index if not exists church_subscription_events_church_idx
  on public.church_subscription_events (church_id, created_at desc);

create index if not exists church_subscription_events_request_idx
  on public.church_subscription_events (request_id, created_at desc)
  where request_id is not null;

alter table public.church_subscription_requests enable row level security;
alter table public.church_subscription_events enable row level security;

drop policy if exists "subscription requests are rpc only"
  on public.church_subscription_requests;
create policy "subscription requests are rpc only"
  on public.church_subscription_requests
  for all
  using (false)
  with check (false);

drop policy if exists "subscription events are rpc only"
  on public.church_subscription_events;
create policy "subscription events are rpc only"
  on public.church_subscription_events
  for all
  using (false)
  with check (false);

drop trigger if exists church_subscription_requests_touch_updated_at
  on public.church_subscription_requests;
create trigger church_subscription_requests_touch_updated_at
  before update on public.church_subscription_requests
  for each row execute function public.touch_updated_at();

create or replace function public.subscription_church_ids(p_church_id text)
returns text[]
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (
      select array_agg(distinct ids.value)
        filter (where ids.value is not null and ids.value <> '')
      from public.churches c
      cross join lateral unnest(array[
        nullif(trim(coalesce(p_church_id, '')), ''),
        nullif(trim(coalesce(c.id::text, '')), ''),
        nullif(trim(coalesce(c."placeId"::text, '')), '')
      ]) as ids(value)
      where c.id::text = nullif(trim(coalesce(p_church_id, '')), '')
         or c."placeId"::text = nullif(trim(coalesce(p_church_id, '')), '')
    ),
    array[nullif(trim(coalesce(p_church_id, '')), '')]::text[]
  );
$$;

create or replace function public.subscription_canonical_church_id(p_church_id text)
returns text
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(
    (
      select coalesce(nullif(trim(c."placeId"::text), ''), c.id::text)
      from public.churches c
      where c.id::text = nullif(trim(coalesce(p_church_id, '')), '')
         or c."placeId"::text = nullif(trim(coalesce(p_church_id, '')), '')
      limit 1
    ),
    nullif(trim(coalesce(p_church_id, '')), '')
  );
$$;

-- A raw UNIQUE(church_id) does not prevent one row using churches.id and a
-- second row using the same church's placeId. Refuse deployment if legacy
-- duplicates appear so finance state is never merged or discarded implicitly.
do $$
begin
  if exists (
    select 1
    from public.churches c
    join public.church_subscriptions cs
      on cs.church_id in (c.id::text, c."placeId"::text)
    where nullif(trim(coalesce(c."placeId"::text, '')), '') is not null
    group by c.id, c."placeId"
    having count(distinct cs.id) > 1
  ) then
    raise exception using
      message = 'Duplicate church subscription aliases detected.',
      hint = 'Reconcile id/placeId subscription rows before applying church subscription management.';
  end if;
end;
$$;

create or replace function public.prevent_church_subscription_alias_duplicate()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if exists (
    select 1
    from public.church_subscriptions cs
    where cs.id <> new.id
      and cs.church_id = any(public.subscription_church_ids(new.church_id))
  ) then
    raise exception 'A subscription already exists for this church id/placeId alias.';
  end if;
  return new;
end;
$$;

drop trigger if exists church_subscriptions_prevent_alias_duplicate
  on public.church_subscriptions;
create trigger church_subscriptions_prevent_alias_duplicate
  before insert or update of church_id on public.church_subscriptions
  for each row execute function public.prevent_church_subscription_alias_duplicate();

-- Finance summaries defensively select one row per canonical church even if a
-- privileged maintenance operation temporarily bypasses the trigger. A valid,
-- current access row wins; ties use the newest update.
create or replace function public.canonical_church_subscriptions()
returns setof public.church_subscriptions
language sql
stable
security definer
set search_path to 'public'
as $$
  select distinct on (public.subscription_canonical_church_id(cs.church_id)) cs.*
  from public.church_subscriptions cs
  order by
    public.subscription_canonical_church_id(cs.church_id),
    case
      when cs.status in ('active', 'trialing', 'grace_period')
       and (
         greatest(
           coalesce(cs.current_period_end, '-infinity'::timestamptz),
           coalesce(cs.free_until, '-infinity'::timestamptz),
           coalesce(cs.grace_until, '-infinity'::timestamptz)
         ) = '-infinity'::timestamptz
         or greatest(
           coalesce(cs.current_period_end, '-infinity'::timestamptz),
           coalesce(cs.free_until, '-infinity'::timestamptz),
           coalesce(cs.grace_until, '-infinity'::timestamptz)
         ) >= now()
       ) then 0
      else 1
    end,
    cs.updated_at desc,
    cs.id desc;
$$;

-- Keep the app-wide subscription gate aligned with the same church id/placeId
-- alias resolution used by subscription management. Without this override, a
-- subscription recorded against one alias can be missed by a membership that
-- retains the other alias.
create or replace function public.get_church_subscription_context(
  p_church_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
  actor_church_id text;
  canonical_church_id text;
  sub public.church_subscriptions;
  active_until timestamptz;
  is_active boolean := false;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  actor_church_id := public.current_active_church_id();
  target_church_id := coalesce(target_church_id, actor_church_id);

  if target_church_id is null then
    return jsonb_build_object(
      'churchId', null,
      'status', 'inactive',
      'planCode', null,
      'source', null,
      'activeUntil', null,
      'isActive', false
    );
  end if;

  if (
    actor_church_id is null
    or actor_church_id <> all(public.subscription_church_ids(target_church_id))
  ) and public.current_developer_role() is null then
    raise exception 'Not authorized for this church subscription.';
  end if;

  canonical_church_id := public.subscription_canonical_church_id(target_church_id);

  select cs.*
    into sub
  from public.church_subscriptions cs
  where cs.church_id = any(public.subscription_church_ids(target_church_id))
  order by cs.updated_at desc
  limit 1;

  if sub.id is null then
    return jsonb_build_object(
      'churchId', canonical_church_id,
      'status', 'inactive',
      'planCode', null,
      'source', null,
      'activeUntil', null,
      'isActive', false
    );
  end if;

  active_until := greatest(
    coalesce(sub.current_period_end, '-infinity'::timestamptz),
    coalesce(sub.free_until, '-infinity'::timestamptz),
    coalesce(sub.grace_until, '-infinity'::timestamptz)
  );

  if active_until = '-infinity'::timestamptz then
    active_until := null;
  end if;

  is_active := sub.status in ('active', 'trialing', 'grace_period')
    and (active_until is null or active_until >= now());

  return jsonb_build_object(
    'churchId', canonical_church_id,
    'status', case when is_active then sub.status else 'inactive' end,
    'rawStatus', sub.status,
    'planCode', sub.plan_code,
    'source', sub.source,
    'activeUntil', active_until,
    'isActive', is_active,
    'isManualFree', sub.source = 'developer_manual',
    'updatedAt', sub.updated_at
  );
end;
$$;

create or replace function public.church_subscription_member_count(p_church_id text)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $$
  select count(distinct cm.user_id)::integer
  from public.church_memberships cm
  where cm.membership_status = 'active'
    and cm.church_id = any(public.subscription_church_ids(p_church_id));
$$;

create or replace function public.church_subscription_tier_for_members(p_member_count integer)
returns jsonb
language sql
immutable
set search_path to 'public'
as $$
  select case
    when greatest(coalesce(p_member_count, 0), 0) <= 50 then
      jsonb_build_object('tierCode', 'tier_0_50', 'label', '0–50 members', 'minMembers', 0, 'maxMembers', 50, 'monthlyUsd', 17, 'monthlyJmd', 2689, 'customQuote', false)
    when p_member_count <= 100 then
      jsonb_build_object('tierCode', 'tier_51_100', 'label', '51–100 members', 'minMembers', 51, 'maxMembers', 100, 'monthlyUsd', 34, 'monthlyJmd', 5377, 'customQuote', false)
    when p_member_count <= 150 then
      jsonb_build_object('tierCode', 'tier_101_150', 'label', '101–150 members', 'minMembers', 101, 'maxMembers', 150, 'monthlyUsd', 51, 'monthlyJmd', 8066, 'customQuote', false)
    when p_member_count <= 200 then
      jsonb_build_object('tierCode', 'tier_151_200', 'label', '151–200 members', 'minMembers', 151, 'maxMembers', 200, 'monthlyUsd', 68, 'monthlyJmd', 10755, 'customQuote', false)
    when p_member_count <= 300 then
      jsonb_build_object('tierCode', 'tier_201_300', 'label', '201–300 members', 'minMembers', 201, 'maxMembers', 300, 'monthlyUsd', 85, 'monthlyJmd', 13444, 'customQuote', false)
    when p_member_count <= 400 then
      jsonb_build_object('tierCode', 'tier_301_400', 'label', '301–400 members', 'minMembers', 301, 'maxMembers', 400, 'monthlyUsd', 102, 'monthlyJmd', 16132, 'customQuote', false)
    when p_member_count <= 500 then
      jsonb_build_object('tierCode', 'tier_401_500', 'label', '401–500 members', 'minMembers', 401, 'maxMembers', 500, 'monthlyUsd', 119, 'monthlyJmd', 18821, 'customQuote', false)
    when p_member_count <= 700 then
      jsonb_build_object('tierCode', 'tier_501_700', 'label', '501–700 members', 'minMembers', 501, 'maxMembers', 700, 'monthlyUsd', 136, 'monthlyJmd', 21510, 'customQuote', false)
    when p_member_count <= 900 then
      jsonb_build_object('tierCode', 'tier_701_900', 'label', '701–900 members', 'minMembers', 701, 'maxMembers', 900, 'monthlyUsd', 153, 'monthlyJmd', 24199, 'customQuote', false)
    when p_member_count <= 1000 then
      jsonb_build_object('tierCode', 'tier_901_1000', 'label', '901–1,000 members', 'minMembers', 901, 'maxMembers', 1000, 'monthlyUsd', 170, 'monthlyJmd', 26887, 'customQuote', false)
    else
      jsonb_build_object('tierCode', 'enterprise_1001_plus', 'label', '1,001+ members', 'minMembers', 1001, 'maxMembers', null, 'monthlyUsd', null, 'monthlyJmd', null, 'customQuote', true)
  end;
$$;

create or replace function public.church_subscription_tier_for_code(p_tier_code text)
returns jsonb
language sql
immutable
set search_path to 'public'
as $$
  select case nullif(trim(coalesce(p_tier_code, '')), '')
    when 'tier_0_50' then public.church_subscription_tier_for_members(0)
    when 'tier_51_100' then public.church_subscription_tier_for_members(51)
    when 'tier_101_150' then public.church_subscription_tier_for_members(101)
    when 'tier_151_200' then public.church_subscription_tier_for_members(151)
    when 'tier_201_300' then public.church_subscription_tier_for_members(201)
    when 'tier_301_400' then public.church_subscription_tier_for_members(301)
    when 'tier_401_500' then public.church_subscription_tier_for_members(401)
    when 'tier_501_700' then public.church_subscription_tier_for_members(501)
    when 'tier_701_900' then public.church_subscription_tier_for_members(701)
    when 'tier_901_1000' then public.church_subscription_tier_for_members(901)
    when 'enterprise_1001_plus' then public.church_subscription_tier_for_members(1001)
    else null
  end;
$$;

create or replace function public.can_manage_church_subscription(p_church_id text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select auth.uid() is not null
    and public.current_active_church_id() = any(public.subscription_church_ids(p_church_id))
    and (
      public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Church Administrator',
        'Admin',
        'Administrator',
        'Treasurer',
        'Financial Secretary',
        'Finance',
        'Finance Officer',
        'Accountant'
      ])
      or public.has_app_privilege('manageChurchSubscription')
      or public.has_app_privilege('manageFinances')
    );
$$;

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
    'developerNotes', p_request.developer_notes,
    'termsVersion', p_request.terms_version,
    'termsLocale', p_request.terms_locale,
    'assignedTo', p_request.assigned_to,
    'createdAt', p_request.created_at,
    'updatedAt', p_request.updated_at,
    'resolvedAt', p_request.resolved_at
  );
$$;

create or replace function public.get_church_subscription_management(
  p_church_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  target_church_id text := coalesce(
    nullif(trim(coalesce(p_church_id, '')), ''),
    public.current_active_church_id()
  );
  canonical_church_id text;
  member_count integer;
  tier jsonb;
  subscription_row public.church_subscriptions;
  church_name text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if target_church_id is null then
    raise exception 'An active church membership is required.';
  end if;

  if not public.can_manage_church_subscription(target_church_id) then
    raise exception 'You do not have permission to manage this church subscription.';
  end if;

  canonical_church_id := public.subscription_canonical_church_id(target_church_id);
  member_count := public.church_subscription_member_count(target_church_id);
  tier := public.church_subscription_tier_for_members(member_count);

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

  return jsonb_build_object(
    'canManage', true,
    'churchId', canonical_church_id,
    'churchName', coalesce(church_name, canonical_church_id),
    'memberCount', member_count,
    'calculatedTier', tier,
    'subscription', case when subscription_row.id is null then null else jsonb_build_object(
      'id', subscription_row.id,
      'status', subscription_row.status,
      'planCode', subscription_row.plan_code,
      'source', subscription_row.source,
      'billingState', subscription_row.billing_state,
      'billingCycle', subscription_row.billing_cycle,
      'autoRenews', subscription_row.auto_renews,
      'autoConverts', subscription_row.auto_converts,
      'nextChargeAt', subscription_row.next_charge_at,
      'cancellationEffectiveAt', subscription_row.cancellation_effective_at,
      'termsVersion', subscription_row.terms_version,
      'memberCountSnapshot', subscription_row.member_count_snapshot,
      'monthlyUsd', subscription_row.monthly_usd,
      'monthlyJmd', subscription_row.monthly_jmd,
      'currentPeriodStart', subscription_row.current_period_start,
      'currentPeriodEnd', subscription_row.current_period_end,
      'graceUntil', subscription_row.grace_until,
      'freeUntil', subscription_row.free_until,
      'updatedAt', subscription_row.updated_at
    ) end,
    'billingTerms', jsonb_build_object(
      'version', '2026-08-11-en-v1',
      'locale', 'en',
      'billingCycle', 'monthly',
      'autoRenews', false,
      'autoConverts', false,
      'requestDoesNotCharge', true,
      'nextChargeAt', null,
      'cancellationMethod', 'Submit a cancellation request in this section. The finance team confirms the effective date.',
      'cancellationHandling', 'Submitting a request does not immediately remove access. Once finance records the cancellation, access ends on the confirmed effective date and no renewal is scheduled.',
      'paidServices', jsonb_build_array(
        'Church member directory and approvals',
        'Attendance, auto-attendance, alerts, and insights',
        'Church announcements, ministries, and study groups',
        'Private prayer care and counseling workflows',
        'Schedules, role management, finance, analytics, and live management'
      ),
      'freeServices', jsonb_build_array(
        'Community and public events',
        'Bible reading and Daily Word',
        'Grace Rooms',
        'Saved items, profile, notifications, and church transfer'
      )
    ),
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
    'history', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', e.id,
        'eventType', e.event_type,
        'status', e.status,
        'planCode', e.plan_code,
        'memberCountSnapshot', e.member_count_snapshot,
        'monthlyUsd', e.monthly_usd,
        'monthlyJmd', e.monthly_jmd,
        'periodEnd', e.period_end,
        'createdAt', e.created_at
      ) order by e.created_at desc), '[]'::jsonb)
      from (
        select cse.*
        from public.church_subscription_events cse
        where cse.church_id = any(public.subscription_church_ids(target_church_id))
        order by cse.created_at desc
        limit 20
      ) e
    )
  );
end;
$$;

-- Remove an earlier six-argument draft if this forward migration was ever
-- partially applied during internal testing. Keeping both overloads would let
-- PostgREST resolve calls without the required Android account channel.
drop function if exists public.submit_church_subscription_request(
  text, text, text, text, text, text
);

create or replace function public.submit_church_subscription_request(
  p_request_type text default 'billing_support',
  p_requested_tier_code text default null,
  p_contact_name text default null,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_message text default null,
  p_channel text default 'android_account_management'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  target_church_id text := public.current_active_church_id();
  canonical_church_id text;
  normalized_type text := lower(trim(coalesce(p_request_type, 'billing_support')));
  member_count integer;
  tier jsonb;
  expected_tier_code text;
  selected_tier_code text;
  selected_tier jsonb;
  request_row public.church_subscription_requests;
  was_created boolean := false;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if target_church_id is null or not public.can_manage_church_subscription(target_church_id) then
    raise exception 'You do not have permission to submit subscription requests.';
  end if;

  -- The Play-distributed Android app is an existing-account management
  -- surface only. Authenticated clients cannot use this RPC to create a new,
  -- changed, or enterprise plan intake that could become an external-payment
  -- funnel. Enrollment intake, if offered by an approved channel, must use a
  -- separately authorized service-side workflow.
  if lower(trim(coalesce(p_channel, ''))) <> 'android_account_management' then
    raise exception 'Unsupported subscription request channel.';
  end if;

  if normalized_type not in ('billing_support', 'cancellation') then
    raise exception 'Plan purchasing and enrollment are unavailable in this Android app.';
  end if;

  if not exists (
    select 1
    from public.church_subscriptions cs
    where cs.church_id = any(public.subscription_church_ids(target_church_id))
  ) then
    raise exception 'Billing support and cancellation are available only for an existing church subscription.';
  end if;

  if nullif(trim(coalesce(p_contact_name, '')), '') is null then
    raise exception 'Contact name is required.';
  end if;

  if nullif(trim(coalesce(p_contact_email, '')), '') is null
     or trim(p_contact_email) !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    raise exception 'A valid contact email is required.';
  end if;

  canonical_church_id := public.subscription_canonical_church_id(target_church_id);
  member_count := public.church_subscription_member_count(target_church_id);
  tier := public.church_subscription_tier_for_members(member_count);
  expected_tier_code := tier ->> 'tierCode';

  selected_tier_code := expected_tier_code;

  if public.church_subscription_tier_for_code(selected_tier_code) is null then
    raise exception 'Unsupported subscription tier.';
  end if;
  selected_tier := public.church_subscription_tier_for_code(selected_tier_code);

  perform pg_advisory_xact_lock(hashtextextended('church_subscription_request:' || canonical_church_id || ':' || normalized_type, 0));

  select csr.*
    into request_row
  from public.church_subscription_requests csr
  where csr.church_id = any(public.subscription_church_ids(canonical_church_id))
    and csr.request_type = normalized_type
    and csr.status in ('pending', 'in_review', 'quoted')
  order by csr.created_at desc
  limit 1
  for update;

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
      message
      ,terms_version
      ,terms_locale
      ,terms_snapshot
    ) values (
      canonical_church_id,
      actor_id,
      normalized_type,
      selected_tier_code,
      member_count,
      case when (selected_tier ->> 'monthlyUsd') is null then null else (selected_tier ->> 'monthlyUsd')::integer end,
      case when (selected_tier ->> 'monthlyJmd') is null then null else (selected_tier ->> 'monthlyJmd')::integer end,
      trim(p_contact_name),
      lower(trim(p_contact_email)),
      nullif(trim(coalesce(p_contact_phone, '')), ''),
      nullif(trim(coalesce(p_message, '')), '')
      ,'2026-08-11-en-v1'
      ,'en'
      ,jsonb_build_object(
        'billingCycle', 'monthly',
        'autoRenews', false,
        'autoConverts', false,
        'requestDoesNotCharge', true,
        'channel', 'android_account_management',
        'monthlyUsd', case when (selected_tier ->> 'monthlyUsd') is null then null else (selected_tier ->> 'monthlyUsd')::integer end,
        'monthlyJmdApproximate', case when (selected_tier ->> 'monthlyJmd') is null then null else (selected_tier ->> 'monthlyJmd')::integer end,
        'cancellationMethod', 'in_app_finance_request'
      )
    )
    returning * into request_row;
    was_created := true;
  else
    update public.church_subscription_requests
    set requested_by = actor_id,
        requested_tier_code = selected_tier_code,
        member_count_snapshot = member_count,
        monthly_usd = case when (selected_tier ->> 'monthlyUsd') is null then null else (selected_tier ->> 'monthlyUsd')::integer end,
        monthly_jmd = case when (selected_tier ->> 'monthlyJmd') is null then null else (selected_tier ->> 'monthlyJmd')::integer end,
        contact_name = trim(p_contact_name),
        contact_email = lower(trim(p_contact_email)),
        contact_phone = nullif(trim(coalesce(p_contact_phone, '')), ''),
        message = nullif(trim(coalesce(p_message, '')), '')
        ,terms_version = '2026-08-11-en-v1'
        ,terms_locale = 'en'
        ,terms_snapshot = jsonb_build_object(
          'billingCycle', 'monthly',
          'autoRenews', false,
          'autoConverts', false,
          'requestDoesNotCharge', true,
          'channel', 'android_account_management',
          'monthlyUsd', case when (selected_tier ->> 'monthlyUsd') is null then null else (selected_tier ->> 'monthlyUsd')::integer end,
          'monthlyJmdApproximate', case when (selected_tier ->> 'monthlyJmd') is null then null else (selected_tier ->> 'monthlyJmd')::integer end,
          'cancellationMethod', 'in_app_finance_request'
        )
    where id = request_row.id
    returning * into request_row;
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
    actor_id,
    case when was_created then 'request_submitted' else 'request_refreshed' end,
    request_row.status,
    selected_tier_code,
    member_count,
    request_row.monthly_usd,
    request_row.monthly_jmd,
    jsonb_build_object(
      'requestType', normalized_type,
      'channel', 'android_account_management'
    )
  );

  update public.church_subscriptions cs
  set last_request_id = request_row.id,
      member_count_snapshot = member_count,
      updated_by = actor_id
  where cs.church_id = any(public.subscription_church_ids(canonical_church_id));

  return public.subscription_request_to_json(request_row)
    - 'developerNotes'
    - 'assignedTo';
end;
$$;

create or replace function public.developer_list_subscription_requests(
  p_status text default null,
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  normalized_status text := nullif(lower(trim(coalesce(p_status, ''))), '');
  normalized_search text := nullif(trim(coalesce(p_search, '')), '');
  safe_limit integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  safe_offset integer := greatest(coalesce(p_offset, 0), 0);
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  if normalized_status is not null and normalized_status not in (
    'pending', 'in_review', 'quoted', 'approved', 'rejected', 'closed', 'cancelled'
  ) then
    raise exception 'Unsupported subscription request status.';
  end if;

  return jsonb_build_object(
    'items', (
      select coalesce(jsonb_agg(public.subscription_request_to_json(r) order by r.created_at desc), '[]'::jsonb)
      from (
        select csr.*
        from public.church_subscription_requests csr
        where (normalized_status is null or csr.status = normalized_status)
          and (
            normalized_search is null
            or csr.contact_name ilike '%' || normalized_search || '%'
            or csr.contact_email ilike '%' || normalized_search || '%'
            or csr.church_id ilike '%' || normalized_search || '%'
            or exists (
              select 1
              from public.churches c
              where (c.id::text = any(public.subscription_church_ids(csr.church_id))
                  or c."placeId"::text = any(public.subscription_church_ids(csr.church_id)))
                and coalesce(c.display_name, c.name, '') ilike '%' || normalized_search || '%'
            )
          )
        order by csr.created_at desc
        limit safe_limit offset safe_offset
      ) r
    ),
    'total', (
      select count(*)
      from public.church_subscription_requests csr
      where (normalized_status is null or csr.status = normalized_status)
        and (
          normalized_search is null
          or csr.contact_name ilike '%' || normalized_search || '%'
          or csr.contact_email ilike '%' || normalized_search || '%'
          or csr.church_id ilike '%' || normalized_search || '%'
          or exists (
            select 1
            from public.churches c
            where (c.id::text = any(public.subscription_church_ids(csr.church_id))
                or c."placeId"::text = any(public.subscription_church_ids(csr.church_id)))
              and coalesce(c.display_name, c.name, '') ilike '%' || normalized_search || '%'
          )
        )
    ),
    'limit', safe_limit,
    'offset', safe_offset
  );
end;
$$;

create or replace function public.developer_update_subscription_request(
  p_request_id uuid,
  p_status text,
  p_developer_notes text default null,
  p_monthly_usd integer default null,
  p_monthly_jmd integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  actor_id uuid := auth.uid();
  request_row public.church_subscription_requests;
  normalized_status text := lower(trim(coalesce(p_status, '')));
  tier jsonb;
  fixed_usd integer;
  fixed_jmd integer;
  allowed boolean := false;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  if normalized_status not in (
    'pending', 'in_review', 'quoted', 'approved', 'rejected', 'closed', 'cancelled'
  ) then
    raise exception 'Unsupported subscription request status.';
  end if;

  select * into request_row
  from public.church_subscription_requests
  where id = p_request_id
  for update;

  if request_row.id is null then
    raise exception 'Subscription request not found.';
  end if;

  if coalesce(p_monthly_usd, 0) < 0 or coalesce(p_monthly_jmd, 0) < 0 then
    raise exception 'Quoted subscription amounts cannot be negative.';
  end if;

  tier := public.church_subscription_tier_for_code(request_row.requested_tier_code);
  fixed_usd := case when (tier ->> 'monthlyUsd') is null then null else (tier ->> 'monthlyUsd')::integer end;
  fixed_jmd := case when (tier ->> 'monthlyJmd') is null then null else (tier ->> 'monthlyJmd')::integer end;

  if request_row.requested_tier_code = 'enterprise_1001_plus'
     and normalized_status = 'quoted'
     and (coalesce(p_monthly_usd, 0) <= 0 or coalesce(p_monthly_jmd, 0) <= 0) then
    raise exception 'Enterprise quotes require positive USD and JMD monthly amounts.';
  end if;

  if request_row.requested_tier_code <> 'enterprise_1001_plus' then
    if p_monthly_usd is not null and p_monthly_usd <> fixed_usd then
      raise exception 'The USD amount for this standard tier is fixed at US$%.', fixed_usd;
    end if;
    if p_monthly_jmd is not null and p_monthly_jmd <> fixed_jmd then
      raise exception 'The JMD amount for this standard tier is fixed at J$%.', fixed_jmd;
    end if;
  end if;

  allowed := request_row.status = normalized_status
    or (request_row.status = 'pending' and normalized_status in ('in_review', 'rejected', 'cancelled'))
    or (request_row.status = 'in_review' and normalized_status in ('quoted', 'approved', 'rejected', 'closed'))
    or (request_row.status = 'quoted' and normalized_status in ('approved', 'rejected', 'closed'))
    or (request_row.status in ('approved', 'rejected') and normalized_status = 'closed');

  if not allowed then
    raise exception 'Invalid request transition from % to %.', request_row.status, normalized_status;
  end if;

  update public.church_subscription_requests
  set status = normalized_status,
      developer_notes = case
        when p_developer_notes is null then developer_notes
        else nullif(trim(p_developer_notes), '')
      end,
      monthly_usd = case
        when requested_tier_code = 'enterprise_1001_plus'
          then coalesce(p_monthly_usd, monthly_usd)
        else fixed_usd
      end,
      monthly_jmd = case
        when requested_tier_code = 'enterprise_1001_plus'
          then coalesce(p_monthly_jmd, monthly_jmd)
        else fixed_jmd
      end,
      assigned_to = case
        when normalized_status in ('in_review', 'quoted', 'approved') then actor_id
        else assigned_to
      end,
      resolved_at = case
        when normalized_status in ('approved', 'rejected', 'closed', 'cancelled') then coalesce(resolved_at, now())
        else null
      end
  where id = request_row.id
  returning * into request_row;

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
    request_row.church_id,
    request_row.id,
    actor_id,
    'request_status_changed',
    request_row.status,
    request_row.requested_tier_code,
    request_row.member_count_snapshot,
    request_row.monthly_usd,
    request_row.monthly_jmd,
    jsonb_build_object('developerRole', dev.developer_role)
  );

  perform public.log_developer_action(
    'subscription_request_status_changed',
    'church_subscription_request',
    request_row.id::text,
    jsonb_build_object(
      'churchId', request_row.church_id,
      'status', request_row.status,
      'requestedTierCode', request_row.requested_tier_code
    )
  );

  return public.subscription_request_to_json(request_row);
end;
$$;

create or replace function public.developer_record_subscription_event(
  p_church_id text,
  p_event_type text,
  p_status text default null,
  p_plan_code text default null,
  p_monthly_usd integer default null,
  p_monthly_jmd integer default null,
  p_period_end timestamptz default null,
  p_notes text default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  actor_id uuid := auth.uid();
  canonical_church_id text := public.subscription_canonical_church_id(p_church_id);
  normalized_event text := lower(trim(coalesce(p_event_type, '')));
  normalized_status text := nullif(lower(trim(coalesce(p_status, ''))), '');
  expected_status text;
  member_count integer;
  calculated_tier jsonb;
  selected_tier jsonb;
  selected_plan_code text;
  fixed_usd integer;
  fixed_jmd integer;
  selected_usd integer;
  selected_jmd integer;
  selected_period_end timestamptz;
  selected_billing_state text;
  sub public.church_subscriptions;
  linked_request public.church_subscription_requests;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  if canonical_church_id is null then
    raise exception 'Church id is required.';
  end if;

  if not exists (
    select 1 from public.churches c
    where c.id::text = any(public.subscription_church_ids(canonical_church_id))
       or c."placeId"::text = any(public.subscription_church_ids(canonical_church_id))
  ) then
    raise exception 'Church not found.';
  end if;

  if normalized_event not in (
    'activated', 'renewed', 'trial_started', 'payment_received',
    'marked_past_due', 'cancelled', 'note'
  ) then
    raise exception 'Unsupported subscription event type.';
  end if;

  if normalized_status is not null and normalized_status not in (
    'active', 'trialing', 'grace_period', 'past_due', 'inactive', 'cancelled'
  ) then
    raise exception 'Unsupported subscription status.';
  end if;

  expected_status := case normalized_event
    when 'activated' then 'active'
    when 'renewed' then 'active'
    when 'payment_received' then 'active'
    when 'trial_started' then 'trialing'
    when 'marked_past_due' then 'past_due'
    when 'cancelled' then 'cancelled'
    else null
  end;

  if normalized_event = 'note' and normalized_status is not null then
    raise exception 'Note events do not change subscription status.';
  end if;

  if expected_status is not null
     and normalized_status is not null
     and normalized_status <> expected_status then
    raise exception 'Event % requires subscription status %.', normalized_event, expected_status;
  end if;

  normalized_status := expected_status;

  if coalesce(p_monthly_usd, 0) < 0 or coalesce(p_monthly_jmd, 0) < 0 then
    raise exception 'Subscription amounts cannot be negative.';
  end if;

  if p_request_id is not null then
    select * into linked_request
    from public.church_subscription_requests csr
    where csr.id = p_request_id
      and csr.church_id = any(public.subscription_church_ids(canonical_church_id));
    if linked_request.id is null then
      raise exception 'The subscription request does not belong to this church.';
    end if;
  end if;

  member_count := public.church_subscription_member_count(canonical_church_id);
  calculated_tier := public.church_subscription_tier_for_members(member_count);
  selected_plan_code := coalesce(
    nullif(trim(coalesce(p_plan_code, '')), ''),
    linked_request.requested_tier_code,
    calculated_tier ->> 'tierCode'
  );
  selected_tier := public.church_subscription_tier_for_code(selected_plan_code);

  if selected_tier is null then
    raise exception 'Unsupported subscription plan code.';
  end if;

  if selected_plan_code <> (calculated_tier ->> 'tierCode') then
    raise exception 'The selected tier no longer matches the church active-member count. Refresh the request and try again.';
  end if;

  fixed_usd := case
    when (selected_tier ->> 'monthlyUsd') is null then null
    else (selected_tier ->> 'monthlyUsd')::integer
  end;
  fixed_jmd := case
    when (selected_tier ->> 'monthlyJmd') is null then null
    else (selected_tier ->> 'monthlyJmd')::integer
  end;

  if selected_plan_code <> 'enterprise_1001_plus' then
    if p_monthly_usd is not null and p_monthly_usd <> fixed_usd then
      raise exception 'The USD amount for % is fixed at US$%.', selected_plan_code, fixed_usd;
    end if;
    if p_monthly_jmd is not null and p_monthly_jmd <> fixed_jmd then
      raise exception 'The JMD amount for % is fixed at J$%.', selected_plan_code, fixed_jmd;
    end if;
  end if;

  selected_usd := case
    when selected_plan_code = 'enterprise_1001_plus'
      then coalesce(p_monthly_usd, linked_request.monthly_usd)
    else fixed_usd
  end;
  selected_jmd := case
    when selected_plan_code = 'enterprise_1001_plus'
      then coalesce(p_monthly_jmd, linked_request.monthly_jmd)
    else fixed_jmd
  end;

  if selected_plan_code = 'enterprise_1001_plus'
     and normalized_event in ('activated', 'renewed', 'payment_received')
     and (selected_usd is null or selected_jmd is null) then
    raise exception 'Enterprise activation requires quoted USD and JMD monthly amounts.';
  end if;

  selected_period_end := case
    when normalized_event in ('activated', 'renewed', 'payment_received', 'trial_started')
      then coalesce(p_period_end, now() + interval '1 month')
    else p_period_end
  end;

  selected_billing_state := case normalized_event
    when 'activated' then 'invoiced'
    when 'renewed' then 'invoiced'
    when 'payment_received' then 'paid'
    when 'trial_started' then 'manual_grant'
    when 'marked_past_due' then 'past_due'
    when 'cancelled' then 'cancelled'
    else null
  end;

  perform pg_advisory_xact_lock(hashtextextended('church_subscription:' || canonical_church_id, 0));

  select cs.* into sub
  from public.church_subscriptions cs
  where cs.church_id = any(public.subscription_church_ids(canonical_church_id))
  order by cs.updated_at desc
  limit 1
  for update;

  if normalized_event <> 'note' then
    if sub.id is null then
      insert into public.church_subscriptions (
        church_id,
        status,
        plan_code,
        source,
        current_period_start,
        current_period_end,
        member_count_snapshot,
        monthly_usd,
        monthly_jmd,
        billing_state,
        billing_cycle,
        auto_renews,
        auto_converts,
        next_charge_at,
        cancellation_effective_at,
        terms_version,
        last_request_id,
        notes,
        created_by,
        updated_by
      ) values (
        canonical_church_id,
        coalesce(normalized_status, 'inactive'),
        selected_plan_code,
        'external_invoice',
        case when normalized_status in ('active', 'trialing') then now() else null end,
        selected_period_end,
        member_count,
        selected_usd,
        selected_jmd,
        coalesce(selected_billing_state, 'not_configured'),
        'monthly',
        false,
        false,
        null,
        case when normalized_event = 'cancelled' then coalesce(p_period_end, now()) else null end,
        '2026-08-11-en-v1',
        p_request_id,
        nullif(trim(coalesce(p_notes, '')), ''),
        actor_id,
        actor_id
      )
      returning * into sub;
    else
      update public.church_subscriptions
      set status = coalesce(normalized_status, status),
          plan_code = selected_plan_code,
          source = 'external_invoice',
          current_period_start = case
            when normalized_event in ('activated', 'renewed', 'payment_received', 'trial_started') then now()
            else current_period_start
          end,
          current_period_end = coalesce(selected_period_end, current_period_end),
          member_count_snapshot = member_count,
          monthly_usd = selected_usd,
          monthly_jmd = selected_jmd,
          billing_state = coalesce(selected_billing_state, billing_state),
          billing_cycle = 'monthly',
          auto_renews = false,
          auto_converts = false,
          next_charge_at = null,
          cancellation_effective_at = case
            when normalized_event = 'cancelled' then coalesce(p_period_end, now())
            when normalized_event in ('activated', 'renewed', 'payment_received', 'trial_started') then null
            else cancellation_effective_at
          end,
          terms_version = '2026-08-11-en-v1',
          last_request_id = coalesce(p_request_id, last_request_id),
          notes = case
            when p_notes is null then notes
            else nullif(trim(p_notes), '')
          end,
          updated_by = actor_id
      where id = sub.id
      returning * into sub;
    end if;
  end if;

  insert into public.church_subscription_events (
    church_id,
    subscription_id,
    request_id,
    actor_user_id,
    event_type,
    status,
    plan_code,
    member_count_snapshot,
    monthly_usd,
    monthly_jmd,
    period_end,
    notes,
    metadata
  ) values (
    canonical_church_id,
    sub.id,
    p_request_id,
    actor_id,
    normalized_event,
    coalesce(normalized_status, sub.status),
    selected_plan_code,
    member_count,
    selected_usd,
    selected_jmd,
    selected_period_end,
    nullif(trim(coalesce(p_notes, '')), ''),
    jsonb_build_object('developerRole', dev.developer_role)
  );

  perform public.log_developer_action(
    'church_subscription_' || normalized_event,
    'church_subscription',
    canonical_church_id,
    jsonb_build_object(
      'requestId', p_request_id,
      'status', coalesce(normalized_status, sub.status),
      'planCode', selected_plan_code,
      'monthlyUsd', selected_usd,
      'monthlyJmd', selected_jmd,
      'periodEnd', selected_period_end
    )
  );

  return jsonb_build_object(
    'churchId', canonical_church_id,
    'eventType', normalized_event,
    'subscription', case when sub.id is null then null else jsonb_build_object(
      'id', sub.id,
      'status', sub.status,
      'planCode', sub.plan_code,
      'source', sub.source,
      'billingState', sub.billing_state,
      'billingCycle', sub.billing_cycle,
      'autoRenews', sub.auto_renews,
      'autoConverts', sub.auto_converts,
      'nextChargeAt', sub.next_charge_at,
      'cancellationEffectiveAt', sub.cancellation_effective_at,
      'termsVersion', sub.terms_version,
      'memberCountSnapshot', sub.member_count_snapshot,
      'monthlyUsd', sub.monthly_usd,
      'monthlyJmd', sub.monthly_jmd,
      'currentPeriodStart', sub.current_period_start,
      'currentPeriodEnd', sub.current_period_end,
      'updatedAt', sub.updated_at
    ) end
  );
end;
$$;

create or replace function public.developer_get_financial_dashboard(
  p_months integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  safe_months integer := least(greatest(coalesce(p_months, 12), 1), 36);
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  return jsonb_build_object(
    'generatedAt', now(),
    'currency', jsonb_build_object('usd', 'USD', 'jmd', 'JMD'),
    'summary', jsonb_build_object(
      'activeSubscriptions', (
        select count(*) from public.canonical_church_subscriptions() cs
        where cs.status = 'active'
          and (cs.current_period_end is null or cs.current_period_end >= now())
      ),
      'trialingSubscriptions', (
        select count(*) from public.canonical_church_subscriptions() cs
        where cs.status = 'trialing'
          and (cs.current_period_end is null or cs.current_period_end >= now())
      ),
      'pastDueSubscriptions', (select count(*) from public.canonical_church_subscriptions() where status = 'past_due'),
      'inactiveSubscriptions', (select count(*) from public.canonical_church_subscriptions() where status in ('inactive', 'cancelled')),
      'openRequests', (select count(*) from public.church_subscription_requests where status in ('pending', 'in_review', 'quoted')),
      'enterpriseRequests', (select count(*) from public.church_subscription_requests where requested_tier_code = 'enterprise_1001_plus' and status in ('pending', 'in_review', 'quoted')),
      'activeMembers', (
        select coalesce(sum(public.church_subscription_member_count(cs.church_id)), 0)
        from public.canonical_church_subscriptions() cs
        where cs.status in ('active', 'trialing', 'grace_period')
          and (cs.current_period_end is null or cs.current_period_end >= now())
      ),
      'monthlyRecurringRevenueUsd', (
        select coalesce(sum(cs.monthly_usd), 0)
        from public.canonical_church_subscriptions() cs
        where cs.status = 'active'
          and cs.billing_state in ('paid', 'invoiced')
          and (cs.current_period_end is null or cs.current_period_end >= now())
      ),
      'monthlyRecurringRevenueJmd', (
        select coalesce(sum(cs.monthly_jmd), 0)
        from public.canonical_church_subscriptions() cs
        where cs.status = 'active'
          and cs.billing_state in ('paid', 'invoiced')
          and (cs.current_period_end is null or cs.current_period_end >= now())
      )
    ),
    'tierDistribution', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'tierCode', tiers.tier_code,
        'label', tiers.label,
        'churchCount', tiers.church_count,
        'members', tiers.members,
        'monthlyUsd', tiers.monthly_usd,
        'monthlyJmd', tiers.monthly_jmd
      ) order by tiers.sort_order), '[]'::jsonb)
      from (
        select
          cs.plan_code as tier_code,
          coalesce(public.church_subscription_tier_for_code(cs.plan_code) ->> 'label', cs.plan_code) as label,
          count(*) as church_count,
          coalesce(sum(public.church_subscription_member_count(cs.church_id)), 0) as members,
          coalesce(sum(cs.monthly_usd), 0) as monthly_usd,
          coalesce(sum(cs.monthly_jmd), 0) as monthly_jmd,
          min(coalesce((public.church_subscription_tier_for_code(cs.plan_code) ->> 'minMembers')::integer, 999999)) as sort_order
        from public.canonical_church_subscriptions() cs
        where cs.status in ('active', 'trialing', 'grace_period')
          and (cs.current_period_end is null or cs.current_period_end >= now())
        group by cs.plan_code
      ) tiers
    ),
    'statusDistribution', (
      select coalesce(jsonb_agg(jsonb_build_object('status', s.status, 'count', s.count) order by s.status), '[]'::jsonb)
      from (
        select status, count(*) as count
        from public.canonical_church_subscriptions()
        group by status
      ) s
    ),
    'monthlyTrend', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'month', to_char(m.month_start, 'YYYY-MM'),
        'requests', (select count(*) from public.church_subscription_requests r where r.created_at >= m.month_start and r.created_at < m.month_start + interval '1 month'),
        'activated', (select count(*) from public.church_subscription_events e where e.event_type in ('activated', 'trial_started') and e.created_at >= m.month_start and e.created_at < m.month_start + interval '1 month'),
        'cancelled', (select count(*) from public.church_subscription_events e where e.event_type = 'cancelled' and e.created_at >= m.month_start and e.created_at < m.month_start + interval '1 month'),
        'revenueUsd', (select coalesce(sum(e.monthly_usd), 0) from public.church_subscription_events e where e.event_type = 'payment_received' and e.created_at >= m.month_start and e.created_at < m.month_start + interval '1 month'),
        'revenueJmd', (select coalesce(sum(e.monthly_jmd), 0) from public.church_subscription_events e where e.event_type = 'payment_received' and e.created_at >= m.month_start and e.created_at < m.month_start + interval '1 month')
      ) order by m.month_start), '[]'::jsonb)
      from generate_series(
        date_trunc('month', now()) - make_interval(months => safe_months - 1),
        date_trunc('month', now()),
        interval '1 month'
      ) as m(month_start)
    ),
    'recentRequests', (
      select coalesce(jsonb_agg(public.subscription_request_to_json(r) order by r.created_at desc), '[]'::jsonb)
      from (
        select * from public.church_subscription_requests
        order by created_at desc
        limit 12
      ) r
    )
  );
end;
$$;

revoke all on table public.church_subscription_requests from anon, authenticated;
revoke all on table public.church_subscription_events from anon, authenticated;

revoke all on function public.subscription_church_ids(text) from public, anon, authenticated;
revoke all on function public.subscription_canonical_church_id(text) from public, anon, authenticated;
revoke all on function public.prevent_church_subscription_alias_duplicate() from public, anon, authenticated;
revoke all on function public.canonical_church_subscriptions() from public, anon, authenticated;
revoke all on function public.church_subscription_member_count(text) from public, anon, authenticated;
revoke all on function public.get_church_subscription_context(text) from public, anon;
revoke all on function public.church_subscription_tier_for_members(integer) from public, anon;
revoke all on function public.church_subscription_tier_for_code(text) from public, anon;
revoke all on function public.can_manage_church_subscription(text) from public, anon;
revoke all on function public.subscription_request_to_json(public.church_subscription_requests) from public, anon, authenticated;
revoke all on function public.get_church_subscription_management(text) from public, anon;
revoke all on function public.submit_church_subscription_request(text, text, text, text, text, text, text) from public, anon;
revoke all on function public.developer_list_subscription_requests(text, text, integer, integer) from public, anon;
revoke all on function public.developer_update_subscription_request(uuid, text, text, integer, integer) from public, anon;
revoke all on function public.developer_record_subscription_event(text, text, text, text, integer, integer, timestamptz, text, uuid) from public, anon;
revoke all on function public.developer_get_financial_dashboard(integer) from public, anon;

-- Retire the original direct grant/clear mutation path. All authenticated
-- finance changes now go through developer_record_subscription_event so the
-- tier is revalidated and an immutable subscription event is recorded.
revoke all on function public.developer_set_church_subscription(text, text, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.developer_clear_church_subscription(text, text)
  from public, anon, authenticated;

grant execute on function public.church_subscription_tier_for_members(integer) to authenticated;
grant execute on function public.church_subscription_tier_for_code(text) to authenticated;
grant execute on function public.can_manage_church_subscription(text) to authenticated;
grant execute on function public.get_church_subscription_context(text) to authenticated;
grant execute on function public.get_church_subscription_management(text) to authenticated;
grant execute on function public.submit_church_subscription_request(text, text, text, text, text, text, text) to authenticated;
grant execute on function public.developer_list_subscription_requests(text, text, integer, integer) to authenticated;
grant execute on function public.developer_update_subscription_request(uuid, text, text, integer, integer) to authenticated;
grant execute on function public.developer_record_subscription_event(text, text, text, text, integer, integer, timestamptz, text, uuid) to authenticated;
grant execute on function public.developer_get_financial_dashboard(integer) to authenticated;
