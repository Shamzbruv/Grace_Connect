-- Developer portal for the canonical church registration/membership workflow.
-- This extends 20260624120000_church_membership_approval_foundation.sql.

create table if not exists public.developer_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  email text unique not null,
  developer_role text not null default 'read_only_support',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid,
  last_login_at timestamptz,
  constraint developer_accounts_role_check check (
    developer_role in (
      'super_developer',
      'support_developer',
      'read_only_support',
      'billing_support',
      'content_moderator',
      'security_admin'
    )
  ),
  constraint developer_accounts_status_check check (status in ('active', 'disabled', 'pending'))
);

create table if not exists public.developer_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  actor_email text,
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.developer_accounts enable row level security;
alter table public.developer_audit_logs enable row level security;

drop policy if exists "No direct developer account reads" on public.developer_accounts;
drop policy if exists "No direct developer audit reads" on public.developer_audit_logs;
create policy "No direct developer account reads" on public.developer_accounts for select using (false);
create policy "No direct developer audit reads" on public.developer_audit_logs for select using (false);

create or replace function public.current_developer_role()
returns text
language sql
security definer
set search_path to 'public'
as $$
  select da.developer_role
  from public.developer_accounts da
  where (
      da.user_id = auth.uid()
      or (da.user_id is null and lower(da.email) = lower(coalesce(auth.jwt()->>'email', '')))
    )
    and da.status = 'active'
  limit 1;
$$;

create or replace function public.require_developer(required_roles text[] default null)
returns public.developer_accounts
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  jwt_email text := lower(coalesce(auth.jwt()->>'email', ''));
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into dev
    from public.developer_accounts
   where (
       user_id = auth.uid()
       or (user_id is null and lower(email) = jwt_email)
     )
     and status = 'active'
   limit 1;

  if dev.id is null then
    raise exception 'Developer access required';
  end if;

  if required_roles is not null and not (dev.developer_role = any(required_roles)) then
    raise exception 'Developer role not permitted for this action';
  end if;

  if dev.user_id is null then
    update public.developer_accounts
       set user_id = auth.uid()
     where id = dev.id
     returning * into dev;
  end if;

  update public.users
     set "isDeveloper" = true
   where id = auth.uid();

  return dev;
end;
$$;

create or replace function public.log_developer_action(
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  insert into public.developer_audit_logs (
    actor_user_id,
    actor_email,
    action,
    target_type,
    target_id,
    details
  )
  values (
    dev.user_id,
    dev.email,
    p_action,
    p_target_type,
    p_target_id,
    coalesce(p_details, '{}'::jsonb)
  );
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
  select count(*)
    into match_count
    from public.churches c
   where normalized_name <> ''
     and (
       lower(regexp_replace(coalesce(c.display_name, c.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name
       or (
         normalized_location <> ''
         and lower(regexp_replace(coalesce(c.location_name, ''), '[^a-z0-9]+', '', 'g')) = normalized_location
       )
       or (
         normalized_address <> ''
         and lower(regexp_replace(coalesce(c.address, ''), '[^a-z0-9]+', '', 'g')) = normalized_address
       )
       or coalesce(c.parish, '') ilike '%' || coalesce(nullif(parish, ''), '__no_parish_match__') || '%'
       or coalesce(c.denomination_label, c.denomination, '') ilike '%' || coalesce(nullif(denomination_id, ''), '__no_denomination_match__') || '%'
     );

  select coalesce(jsonb_agg(jsonb_build_object(
    'name', coalesce(nullif(c.display_name, ''), nullif(c.name, ''), 'Possible match'),
    'address', c.address,
    'parish', c.parish,
    'status', case when c.church_status = 'approved' then 'registered' else 'under_review' end
  )), '[]'::jsonb)
    into safe_matches
    from (
      select *
      from public.churches c
      where normalized_name <> ''
        and (
          lower(regexp_replace(coalesce(c.display_name, c.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name
          or (
            normalized_location <> ''
            and lower(regexp_replace(coalesce(c.location_name, ''), '[^a-z0-9]+', '', 'g')) = normalized_location
          )
          or (
            normalized_address <> ''
            and lower(regexp_replace(coalesce(c.address, ''), '[^a-z0-9]+', '', 'g')) = normalized_address
          )
        )
      order by c."createdAt" desc nulls last
      limit 5
    ) c;

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

create or replace function public.developer_get_session()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  update public.developer_accounts
     set last_login_at = now()
   where id = dev.id;

  return jsonb_build_object(
    'user_id', dev.user_id,
    'email', dev.email,
    'developer_role', dev.developer_role,
    'status', dev.status
  );
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
        crr.pastor_email as pastor_or_admin_email,
        crr.pastor_phone as pastor_or_admin_phone,
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
        u.email,
        u."fullName",
        u.phone,
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
        u.email,
        u."fullName",
        u.phone,
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

create or replace function public.developer_approve_church_registration(p_church_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  request_uuid uuid;
  approved_church_id text;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  begin
    request_uuid := p_church_id::uuid;
  exception when others then
    request_uuid := null;
  end;

  if request_uuid is not null
     and exists (select 1 from public.church_registration_requests where id = request_uuid) then
    approved_church_id := public.approve_church_registration(request_uuid, 'Approved from developer portal.');
    perform public.log_developer_action('church_registration_approved', 'church_registration_request', request_uuid::text, jsonb_build_object('churchId', approved_church_id));
    return jsonb_build_object('ok', true, 'church_id', approved_church_id);
  end if;

  update public.churches
     set church_status = 'approved',
         status = 'active',
         public_visibility = true,
         approved_at = coalesce(approved_at, now()),
         approved_by = dev.user_id,
         updated_at = now()
   where id = p_church_id or "placeId" = p_church_id
   returning coalesce("placeId", id) into approved_church_id;

  if approved_church_id is null then
    raise exception 'Church registration request or church not found';
  end if;

  perform public.log_developer_action('church_approved', 'church', approved_church_id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'church_id', approved_church_id);
end;
$$;

create or replace function public.developer_reject_church_registration(
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
  request_uuid uuid;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  begin
    request_uuid := p_church_id::uuid;
  exception when others then
    request_uuid := null;
  end;

  if request_uuid is not null
     and exists (select 1 from public.church_registration_requests where id = request_uuid) then
    perform public.reject_church_registration(request_uuid, p_reason);
    perform public.log_developer_action('church_registration_rejected', 'church_registration_request', request_uuid::text, jsonb_build_object('reason', p_reason));
    return jsonb_build_object('ok', true);
  end if;

  update public.churches
     set church_status = 'suspended',
         status = 'suspended',
         public_visibility = false,
         updated_at = now()
   where id = p_church_id or "placeId" = p_church_id;

  perform public.log_developer_action('church_rejected_or_hidden', 'church', p_church_id, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_suspend_church(
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
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  update public.churches
     set church_status = 'suspended',
         status = 'suspended',
         public_visibility = false,
         updated_at = now()
   where id = p_church_id or "placeId" = p_church_id;

  perform public.log_developer_action('church_suspended', 'church', p_church_id, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_approve_member_request(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
  church_name text;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

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
         decision_reason = 'Approved from developer portal.'
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

  perform public.log_developer_action('member_request_approved', 'church_membership', target.id::text, jsonb_build_object('userId', target.user_id, 'churchId', target.church_id));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_reject_member_request(
  p_user_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  select *
    into target
  from public.church_memberships
  where id = p_user_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found';
  end if;

  update public.church_memberships
     set membership_status = 'declined',
         reviewed_by = dev.user_id,
         reviewed_at = now(),
         decision_reason = nullif(trim(coalesce(p_reason, '')), '')
   where id = target.id;

  update public.users
     set "accountState" = 'declined',
         "placeId" = null,
         "placeName" = null,
         roles = array['Member']
   where id = target.user_id
     and not exists (
       select 1
       from public.church_memberships
       where user_id = target.user_id
         and membership_status = 'active'
     );

  perform public.log_developer_action('member_request_rejected', 'church_membership', target.id::text, jsonb_build_object('reason', p_reason, 'userId', target.user_id, 'churchId', target.church_id));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_list_developer_accounts()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select id, user_id, email, developer_role, status, created_at, created_by, last_login_at
      from public.developer_accounts
      order by created_at desc
    ) r
  );
end;
$$;

create or replace function public.developer_upsert_developer_account(
  p_email text,
  p_developer_role text default 'read_only_support',
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target_auth_user auth.users;
  target_public_user public.users;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  if nullif(trim(p_email), '') is null then
    raise exception 'Email is required';
  end if;

  select * into target_auth_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  select * into target_public_user
  from public.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  insert into public.developer_accounts (
    user_id,
    email,
    developer_role,
    status,
    created_by
  )
  values (
    coalesce(target_auth_user.id, target_public_user.id),
    lower(trim(p_email)),
    p_developer_role,
    p_status,
    dev.user_id
  )
  on conflict (email) do update
    set user_id = coalesce(excluded.user_id, public.developer_accounts.user_id),
        developer_role = excluded.developer_role,
        status = excluded.status;

  if coalesce(target_auth_user.id, target_public_user.id) is not null then
    update public.users
       set "isDeveloper" = (p_status = 'active')
     where id = coalesce(target_auth_user.id, target_public_user.id);
  end if;

  perform public.log_developer_action('developer_account_upserted', 'developer_account', lower(trim(p_email)), jsonb_build_object('developer_role', p_developer_role, 'status', p_status));
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_remove_developer_access(p_email text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target public.developer_accounts;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  select * into target
  from public.developer_accounts
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target.id is null then
    raise exception 'Developer account not found';
  end if;

  if target.user_id = dev.user_id then
    raise exception 'You cannot remove your own developer access from the portal';
  end if;

  update public.developer_accounts
     set status = 'disabled'
   where id = target.id;

  update public.users
     set "isDeveloper" = false
   where id = target.user_id;

  perform public.log_developer_action('developer_account_disabled', 'developer_account', lower(trim(p_email)), '{}'::jsonb);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.developer_get_audit_logs(p_limit integer default 80)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin', 'support_developer']);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select id, actor_user_id, actor_email, action, target_type, target_id, details, created_at
      from public.developer_audit_logs
      order by created_at desc
      limit greatest(1, least(coalesce(p_limit, 80), 200))
    ) r
  );
end;
$$;

grant execute on function public.current_developer_role() to authenticated;
grant execute on function public.require_developer(text[]) to authenticated;
grant execute on function public.log_developer_action(text, text, text, jsonb) to authenticated;
grant execute on function public.check_church_registration_conflicts(text, text, text, text, text) to anon, authenticated;
grant execute on function public.developer_get_session() to authenticated;
grant execute on function public.developer_get_dashboard() to authenticated;
grant execute on function public.developer_list_churches(text, text) to authenticated;
grant execute on function public.developer_list_member_requests(text) to authenticated;
grant execute on function public.developer_search_users(text, text) to authenticated;
grant execute on function public.developer_approve_church_registration(text) to authenticated;
grant execute on function public.developer_reject_church_registration(text, text) to authenticated;
grant execute on function public.developer_suspend_church(text, text) to authenticated;
grant execute on function public.developer_approve_member_request(uuid) to authenticated;
grant execute on function public.developer_reject_member_request(uuid, text) to authenticated;
grant execute on function public.developer_list_developer_accounts() to authenticated;
grant execute on function public.developer_upsert_developer_account(text, text, text) to authenticated;
grant execute on function public.developer_remove_developer_access(text) to authenticated;
grant execute on function public.developer_get_audit_logs(integer) to authenticated;

-- Bootstrap your owner account once, replacing the email before execution if you
-- want it inside a migration. The first portal login links user_id automatically.
-- insert into public.developer_accounts (email, developer_role, status)
-- values (lower('owner@graceconnect.app'), 'super_developer', 'active')
-- on conflict (email) do update set developer_role = 'super_developer', status = 'active';
