-- Church-level subscription source of truth for the app and developer portal.
-- The mobile app only unlocks non-feed sections when the user's church has an
-- active subscription row. Developers can grant manual/free access here; Google
-- Play billing reconciliation can update the same table by purchase token later.

create table if not exists public.church_subscriptions (
  id uuid primary key default gen_random_uuid(),
  church_id text not null unique,
  status text not null default 'inactive'
    check (status in ('active', 'trialing', 'grace_period', 'past_due', 'inactive', 'cancelled')),
  plan_code text not null default 'manual_free',
  source text not null default 'developer_manual'
    check (source in ('developer_manual', 'google_play', 'system')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  grace_until timestamptz,
  free_until timestamptz,
  google_product_id text,
  google_purchase_token text,
  google_order_id text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists church_subscriptions_status_idx
  on public.church_subscriptions (status);

create index if not exists church_subscriptions_google_purchase_token_idx
  on public.church_subscriptions (google_purchase_token)
  where google_purchase_token is not null;

alter table public.church_subscriptions enable row level security;

drop policy if exists "church subscriptions are rpc only" on public.church_subscriptions;
create policy "church subscriptions are rpc only"
  on public.church_subscriptions
  for all
  using (false)
  with check (false);

create or replace function public.touch_church_subscriptions_updated_at()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists church_subscriptions_touch_updated_at on public.church_subscriptions;
create trigger church_subscriptions_touch_updated_at
  before update on public.church_subscriptions
  for each row execute function public.touch_church_subscriptions_updated_at();

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
  sub record;
  active_until timestamptz;
  is_active boolean := false;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  actor_church_id := public.get_church_id();
  target_church_id := coalesce(target_church_id, actor_church_id);

  if target_church_id is null or target_church_id = '' then
    return jsonb_build_object(
      'churchId', null,
      'status', 'inactive',
      'planCode', null,
      'source', null,
      'activeUntil', null,
      'isActive', false
    );
  end if;

  if target_church_id <> actor_church_id
     and public.current_developer_role() is null then
    raise exception 'Not authorized for this church subscription.';
  end if;

  select *
    into sub
  from public.church_subscriptions
  where church_id = target_church_id
  limit 1;

  if sub.id is null then
    return jsonb_build_object(
      'churchId', target_church_id,
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
    'churchId', target_church_id,
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

create or replace function public.developer_set_church_subscription(
  p_church_id text,
  p_status text default 'active',
  p_plan_code text default 'manual_free',
  p_months integer default 1,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  actor_id uuid := auth.uid();
  target_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
  normalized_status text := lower(trim(coalesce(p_status, 'active')));
  normalized_plan text := nullif(trim(coalesce(p_plan_code, 'manual_free')), '');
  active_until timestamptz;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  if target_church_id is null then
    raise exception 'Church id is required.';
  end if;

  if normalized_status not in ('active', 'trialing', 'grace_period', 'past_due', 'inactive', 'cancelled') then
    raise exception 'Unsupported subscription status: %', normalized_status;
  end if;

  if p_months is not null and p_months > 0 then
    active_until := now() + make_interval(months => p_months);
  else
    active_until := null;
  end if;

  insert into public.church_subscriptions (
    church_id,
    status,
    plan_code,
    source,
    current_period_start,
    current_period_end,
    free_until,
    notes,
    created_by,
    updated_by
  )
  values (
    target_church_id,
    normalized_status,
    coalesce(normalized_plan, 'manual_free'),
    'developer_manual',
    now(),
    active_until,
    active_until,
    nullif(trim(coalesce(p_notes, '')), ''),
    actor_id,
    actor_id
  )
  on conflict (church_id) do update
    set status = excluded.status,
        plan_code = excluded.plan_code,
        source = excluded.source,
        current_period_start = excluded.current_period_start,
        current_period_end = excluded.current_period_end,
        free_until = excluded.free_until,
        grace_until = null,
        notes = excluded.notes,
        updated_by = actor_id,
        metadata = public.church_subscriptions.metadata || jsonb_build_object(
          'lastManualGrantMonths', p_months,
          'lastManualGrantBy', dev.email
        );

  perform public.log_developer_action(
    'church_subscription_set',
    'church_subscription',
    target_church_id,
    jsonb_build_object(
      'status', normalized_status,
      'planCode', coalesce(normalized_plan, 'manual_free'),
      'months', p_months,
      'activeUntil', active_until,
      'notes', nullif(trim(coalesce(p_notes, '')), '')
    )
  );

  return public.get_church_subscription_context(target_church_id);
end;
$$;

create or replace function public.developer_clear_church_subscription(
  p_church_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  actor_id uuid := auth.uid();
  target_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
begin
  select * into dev
  from public.require_developer(array['super_developer', 'billing_support', 'security_admin']);

  if target_church_id is null then
    raise exception 'Church id is required.';
  end if;

  insert into public.church_subscriptions (
    church_id,
    status,
    plan_code,
    source,
    current_period_end,
    free_until,
    notes,
    created_by,
    updated_by
  )
  values (
    target_church_id,
    'inactive',
    'manual_free',
    'developer_manual',
    now(),
    now(),
    nullif(trim(coalesce(p_reason, '')), ''),
    actor_id,
    actor_id
  )
  on conflict (church_id) do update
    set status = 'inactive',
        current_period_end = now(),
        free_until = now(),
        grace_until = null,
        notes = nullif(trim(coalesce(p_reason, '')), ''),
        updated_by = actor_id,
        metadata = public.church_subscriptions.metadata || jsonb_build_object(
          'lastManualDisableBy', dev.email
        );

  perform public.log_developer_action(
    'church_subscription_cleared',
    'church_subscription',
    target_church_id,
    jsonb_build_object('reason', nullif(trim(coalesce(p_reason, '')), ''))
  );

  return public.get_church_subscription_context(target_church_id);
end;
$$;

create or replace function public.developer_get_dashboard()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  return jsonb_build_object(
    'total_users', (select count(*) from public.users),
    'pending_members', (select count(*) from public.church_memberships where membership_status = 'pending'),
    'total_churches', (select count(*) from public.churches),
    'approved_churches', (select count(*) from public.churches where church_status = 'approved'),
    'pending_churches', (select count(*) from public.church_registration_requests where application_status in ('submitted', 'under_review', 'needs_information')),
    'suspended_churches', (select count(*) from public.churches where church_status = 'suspended'),
    'subscribed_churches', (
      select count(*)
      from public.churches c
      where exists (
        select 1
        from public.church_subscriptions cs
        where cs.church_id in (c.id::text, c."placeId"::text)
          and cs.status in ('active', 'trialing', 'grace_period')
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
          )
      )
    ),
    'unsubscribed_churches', (
      select count(*)
      from public.churches c
      where c.church_status = 'approved'
        and not exists (
          select 1
          from public.church_subscriptions cs
          where cs.church_id in (c.id::text, c."placeId"::text)
            and cs.status in ('active', 'trialing', 'grace_period')
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
            )
        )
    ),
    'developer_accounts', (select count(*) from public.developer_accounts where status = 'active'),
    'recent_signups', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from (
        select id, email, "fullName", "placeName", "accountState" as "approvalStatus", "joinDate"
        from public.users
        order by "joinDate" desc nulls last
        limit 8
      ) r
    ),
    'churches_missing_setup', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from (
        select c.id, c."placeId", coalesce(c.display_name, c.name) as name, c.address, c."ownerUserId"
        from public.churches c
        where c.church_status = 'approved'
          and (coalesce(c."ownerUserId", '') = '' or c.address is null or c.address = '')
        order by c."createdAt" desc nulls last
        limit 8
      ) r
    )
  );
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
        0::bigint as member_count,
        'inactive'::text as subscription_status,
        false as subscription_active,
        null::text as subscription_plan_code,
        null::text as subscription_source,
        null::timestamptz as subscription_active_until
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
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId", c.id::text) as name,
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
        (select count(*) from public.church_memberships cm where cm.church_id in (c.id::text, c."placeId"::text) and cm.membership_status = 'active') as member_count,
        coalesce(case when sub.is_active then sub.status else 'inactive' end, 'inactive') as subscription_status,
        coalesce(sub.is_active, false) as subscription_active,
        sub.plan_code as subscription_plan_code,
        sub.source as subscription_source,
        sub.active_until as subscription_active_until
      from public.churches c
      left join lateral (
        select
          cs.status,
          cs.plan_code,
          cs.source,
          nullif(
            greatest(
              coalesce(cs.current_period_end, '-infinity'::timestamptz),
              coalesce(cs.free_until, '-infinity'::timestamptz),
              coalesce(cs.grace_until, '-infinity'::timestamptz)
            ),
            '-infinity'::timestamptz
          ) as active_until,
          cs.status in ('active', 'trialing', 'grace_period')
            and (
              nullif(
                greatest(
                  coalesce(cs.current_period_end, '-infinity'::timestamptz),
                  coalesce(cs.free_until, '-infinity'::timestamptz),
                  coalesce(cs.grace_until, '-infinity'::timestamptz)
                ),
                '-infinity'::timestamptz
              ) is null
              or greatest(
                coalesce(cs.current_period_end, '-infinity'::timestamptz),
                coalesce(cs.free_until, '-infinity'::timestamptz),
                coalesce(cs.grace_until, '-infinity'::timestamptz)
              ) >= now()
            ) as is_active
        from public.church_subscriptions cs
        where cs.church_id in (c.id::text, c."placeId"::text)
        order by cs.updated_at desc
        limit 1
      ) sub on true
      where (
          nullif(trim(coalesce(p_status, '')), '') is null
          or lower(c.church_status) = lower(p_status)
          or (lower(p_status) = 'approved' and c.church_status = 'approved')
          or (lower(p_status) = 'subscribed' and sub.is_active is true)
          or (lower(p_status) = 'unsubscribed' and coalesce(sub.is_active, false) is false)
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

grant execute on function public.get_church_subscription_context(text) to authenticated;
grant execute on function public.developer_set_church_subscription(text, text, text, integer, text) to authenticated;
grant execute on function public.developer_clear_church_subscription(text, text) to authenticated;
grant execute on function public.developer_get_dashboard() to authenticated;
grant execute on function public.developer_list_churches(text, text) to authenticated;
