-- Developer portal user management controls.
-- Keeps church-admin approval as the normal path while giving platform developers
-- explicit support tools for approval, account deletion, roles, and privileges.

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
        u.id::text as id,
        u.uid,
        case when dev.developer_role in ('super_developer', 'security_admin') then u.email
             when u.email is not null and position('@' in u.email) > 0 then substr(u.email, 1, 3) || '***@' || split_part(u.email, '@', 2)
             else u.email end as email,
        u."fullName",
        case when dev.developer_role in ('super_developer', 'security_admin') then u.phone
             when u.phone is not null and length(u.phone) >= 4 then '***-***-' || right(u.phone, 4)
             else u.phone end as phone,
        coalesce(active_membership.church_id, pending_membership.church_id, u."placeId") as "placeId",
        coalesce(active_membership.church_name, pending_membership.church_name, u."placeName") as "placeName",
        u.roles,
        coalesce(u."appPrivileges", '{}'::text[]) as "appPrivileges",
        u."accountState",
        coalesce(active_membership.membership_status, pending_membership.membership_status, latest_membership.membership_status, u."accountState") as "approvalStatus",
        pending_membership.id::text as "pendingMembershipId",
        pending_membership.church_id as "pendingChurchId",
        pending_membership.church_name as "pendingChurchName",
        latest_membership.membership_status as "membershipStatus",
        latest_membership.id::text as "latestMembershipId",
        u."isDeveloper",
        u."joinDate"
      from public.users u
      left join lateral (
        select
          cm.id,
          cm.church_id,
          cm.membership_status,
          coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id) as church_name
        from public.church_memberships cm
        left join public.churches c on c.id = cm.church_id or c."placeId" = cm.church_id
        where cm.user_id = u.id
          and cm.membership_status = 'active'
        order by cm.reviewed_at desc nulls last, cm.updated_at desc nulls last
        limit 1
      ) active_membership on true
      left join lateral (
        select
          cm.id,
          cm.church_id,
          cm.membership_status,
          coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id) as church_name
        from public.church_memberships cm
        left join public.churches c on c.id = cm.church_id or c."placeId" = cm.church_id
        where cm.user_id = u.id
          and cm.membership_status = 'pending'
        order by cm.requested_at desc nulls last, cm.updated_at desc nulls last
        limit 1
      ) pending_membership on true
      left join lateral (
        select cm.id, cm.membership_status
        from public.church_memberships cm
        where cm.user_id = u.id
        order by cm.updated_at desc nulls last
        limit 1
      ) latest_membership on true
      where (
          nullif(trim(coalesce(p_search, '')), '') is null
          or coalesce(u."fullName", '') ilike '%' || trim(p_search) || '%'
          or coalesce(u.email, '') ilike '%' || trim(p_search) || '%'
          or coalesce(u."placeName", '') ilike '%' || trim(p_search) || '%'
          or coalesce(active_membership.church_name, '') ilike '%' || trim(p_search) || '%'
          or coalesce(pending_membership.church_name, '') ilike '%' || trim(p_search) || '%'
        )
        and (
          nullif(trim(coalesce(p_church_id, '')), '') is null
          or u."placeId" = p_church_id
          or active_membership.church_id = p_church_id
          or pending_membership.church_id = p_church_id
        )
      order by u."joinDate" desc nulls last
      limit 200
    ) r
  );
end;
$$;

create or replace function public.developer_get_church_detail(p_church_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
  members jsonb;
begin
  select * into dev from public.require_developer(null);

  select *
    into target
  from public.churches c
  where c.id::text = p_church_id or c."placeId"::text = p_church_id
  limit 1;

  if target.id is null then
    raise exception 'Church not found.';
  end if;

  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
    into members
  from (
    select
      cm.id::text as membership_id,
      cm.membership_status,
      cm.requested_at,
      cm.reviewed_at,
      u.id::text as user_id,
      u.uid,
      case when dev.developer_role in ('super_developer', 'security_admin') then u.email
           when u.email is not null and position('@' in u.email) > 0 then substr(u.email, 1, 3) || '***@' || split_part(u.email, '@', 2)
           else u.email end as email,
      u."fullName" as full_name,
      case when dev.developer_role in ('super_developer', 'security_admin') then u.phone
           when u.phone is not null and length(u.phone) >= 4 then '***-***-' || right(u.phone, 4)
           else u.phone end as phone,
      u.roles,
      coalesce(u."appPrivileges", '{}'::text[]) as app_privileges,
      u."isDeveloper" as is_developer,
      u."accountState" as account_state
    from public.church_memberships cm
    left join public.users u on u.id = cm.user_id or u.uid = cm.user_id::text
    where cm.church_id in (target.id::text, target."placeId"::text)
    order by
      case cm.membership_status when 'active' then 1 when 'pending' then 2 else 3 end,
      coalesce(u."fullName", u.email, '') asc
  ) m;

  return jsonb_build_object(
    'church', to_jsonb(target),
    'members', members
  );
end;
$$;

create or replace function public.developer_approve_member_request(
  p_membership_id text,
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
  church_name text;
  target_email text;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  select cm.*, u.email
    into target
  from public.church_memberships cm
  left join public.users u on u.id = cm.user_id
  where cm.id::text = p_membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;

  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be approved.';
  end if;

  select coalesce(nullif(display_name, ''), nullif(name, ''), target.church_id)
    into church_name
  from public.churches
  where id = target.church_id or "placeId" = target.church_id
  limit 1;

  update public.church_memberships
     set membership_status = 'active',
         reviewed_by = dev.user_id,
         reviewed_at = now(),
         decision_reason = coalesce(nullif(trim(p_reason), ''), 'Approved from developer portal.')
   where id = target.id;

  update public.church_memberships
     set membership_status = 'cancelled',
         decision_reason = 'Cancelled because another church membership was approved.'
   where user_id = target.user_id
     and id <> target.id
     and membership_status = 'pending';

  update public.users
     set "placeId" = target.church_id,
         "placeName" = coalesce(church_name, target.church_id),
         "accountState" = 'active',
         roles = case when roles is null or array_length(roles, 1) is null then array['Member'] else roles end
   where id = target.user_id
   returning email into target_email;

  begin
    perform public.queue_app_email(
      target_email,
      'Grace Connect membership approved',
      'Your request to join ' || coalesce(church_name, 'your church') || ' was approved. You can now open Grace Connect and use your church features.',
      'Your request to join ' || coalesce(church_name, 'your church') || ' was approved. You can now open Grace Connect and use your church features.',
      'church_membership',
      target.id::text,
      target.user_id,
      jsonb_build_object(
        'type', 'membership_approved',
        'churchId', target.church_id,
        'membershipId', target.id::text,
        'approvedBy', dev.email
      )
    );
  exception when undefined_function then
    null;
  end;

  begin
    perform public.create_notification(
      target.user_id,
      dev.user_id,
      'membership_approved',
      'Membership approved',
      'Your request to join ' || coalesce(church_name, 'this church') || ' was approved.',
      target.church_id,
      'church_memberships',
      target.id::text,
      '/dashboard'
    );
  exception when undefined_function then
    null;
  end;

  perform public.log_developer_action(
    'member_request_approved',
    'church_membership',
    target.id::text,
    jsonb_build_object('userId', target.user_id, 'churchId', target.church_id, 'reason', coalesce(nullif(trim(p_reason), ''), 'Approved from developer portal.'))
  );

  return jsonb_build_object('ok', true, 'user_id', target.user_id, 'church_id', target.church_id);
end;
$$;

create or replace function public.developer_update_user_access(
  p_user_id text,
  p_roles text[] default null,
  p_app_privileges text[] default null,
  p_account_state text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target public.users;
  cleaned_roles text[];
  cleaned_privileges text[];
  clean_account_state text;
  active_membership_id uuid;
  role_value text;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  select *
    into target
  from public.users
  where id::text = trim(coalesce(p_user_id, ''))
     or uid = trim(coalesce(p_user_id, ''))
     or lower(email) = lower(trim(coalesce(p_user_id, '')))
  limit 1;

  if target.id is null then
    raise exception 'User account not found.';
  end if;

  select coalesce(array_agg(distinct role_name order by role_name), array['Member']::text[])
    into cleaned_roles
  from (
    select trim(value) as role_name
    from unnest(coalesce(p_roles, target.roles, array['Member']::text[])) as value
    where trim(value) <> ''
      and length(trim(value)) <= 96
  ) roles;

  if cleaned_roles is null or array_length(cleaned_roles, 1) is null then
    cleaned_roles := array['Member']::text[];
  end if;

  select coalesce(array_agg(distinct privilege_name order by privilege_name), '{}'::text[])
    into cleaned_privileges
  from (
    select trim(value) as privilege_name
    from unnest(coalesce(p_app_privileges, target."appPrivileges", '{}'::text[])) as value
    where trim(value) = any(array[
      'approveMembers',
      'manageChurchSettings',
      'manageRoles',
      'viewOperationalAnalytics',
      'viewFinanceDashboard',
      'manageFinances',
      'approveFinanceReports',
      'createAnnouncement',
      'sendPushNotification',
      'pinPost',
      'moderateCommunity',
      'createEvents',
      'manageSundaySchool',
      'manageLivestream',
      'manageWorship',
      'managePrayerRequests',
      'assignCareRequests',
      'manualCheckIn',
      'viewAttendanceInsights',
      'viewPriorityList',
      'managePriorityList',
      'manageSchedule'
    ])
  ) privileges;

  clean_account_state := nullif(trim(coalesce(p_account_state, target."accountState")), '');
  if clean_account_state is not null and clean_account_state not in (
    'active',
    'pending',
    'declined',
    'removed',
    'suspended',
    'disabled',
    'deleted',
    'deletion_requested'
  ) then
    raise exception 'Unsupported account state: %', clean_account_state;
  end if;

  update public.users
     set roles = cleaned_roles,
         "appPrivileges" = cleaned_privileges,
         "accountState" = coalesce(clean_account_state, "accountState")
   where id = target.id;

  select cm.id
    into active_membership_id
  from public.church_memberships cm
  where cm.user_id = target.id
    and cm.membership_status = 'active'
  order by cm.reviewed_at desc nulls last, cm.updated_at desc nulls last
  limit 1;

  if active_membership_id is not null then
    update public.church_member_roles
       set revoked_at = now()
     where membership_id = active_membership_id
       and revoked_at is null
       and not (role_name = any(cleaned_roles));

    foreach role_value in array cleaned_roles loop
      insert into public.church_member_roles (membership_id, role_name, assigned_by)
      values (active_membership_id, role_value, dev.user_id)
      on conflict (membership_id, role_name) do update
        set revoked_at = null,
            assigned_by = excluded.assigned_by,
            assigned_at = now();
    end loop;
  end if;

  begin
    perform public.create_notification(
      target.id,
      dev.user_id,
      'role_changed',
      'Access updated',
      'Your Grace Connect roles or app privileges were updated by platform support.',
      target."placeId",
      'users',
      target.id::text,
      '/notifications'
    );
  exception when undefined_function then
    null;
  end;

  perform public.log_developer_action(
    'user_access_updated',
    'user',
    target.id::text,
    jsonb_build_object(
      'roles', cleaned_roles,
      'appPrivileges', cleaned_privileges,
      'accountState', clean_account_state,
      'email', target.email
    )
  );

  return jsonb_build_object(
    'ok', true,
    'user_id', target.id,
    'roles', cleaned_roles,
    'appPrivileges', cleaned_privileges,
    'accountState', clean_account_state
  );
end;
$$;

create or replace function public.developer_delete_user_account(
  p_user_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  clean_identifier text := trim(coalesce(p_user_id, ''));
  parsed_user_id uuid;
  target_public public.users;
  target_auth auth.users;
  target_user_id uuid;
  target_email text;
  target_name text;
  target_is_developer boolean;
begin
  select * into dev from public.require_developer(array['super_developer', 'security_admin']);

  if clean_identifier = '' then
    raise exception 'User identifier is required.';
  end if;

  begin
    parsed_user_id := clean_identifier::uuid;
  exception when others then
    parsed_user_id := null;
  end;

  select *
    into target_public
  from public.users
  where id = parsed_user_id
     or id::text = clean_identifier
     or uid = clean_identifier
     or lower(email) = lower(clean_identifier)
  limit 1;

  if target_public.id is not null then
    target_user_id := target_public.id;
    target_email := target_public.email;
    target_name := target_public."fullName";
  end if;

  if target_user_id is null and parsed_user_id is not null then
    select *
      into target_auth
    from auth.users
    where id = parsed_user_id
    limit 1;

    if target_auth.id is not null then
      target_user_id := target_auth.id;
      target_email := target_auth.email;
      target_name := coalesce(target_auth.raw_user_meta_data->>'fullName', target_auth.raw_user_meta_data->>'name');
    end if;
  end if;

  if target_user_id is null then
    raise exception 'User account not found.';
  end if;

  if target_user_id = dev.user_id then
    raise exception 'You cannot delete your own developer account from the portal.';
  end if;

  select exists (
    select 1
    from public.developer_accounts da
    where da.status = 'active'
      and (
        da.user_id = target_user_id
        or (target_email is not null and lower(da.email) = lower(target_email))
      )
  ) into target_is_developer;

  if target_is_developer and dev.developer_role <> 'super_developer' then
    raise exception 'Only a super developer can delete another developer account.';
  end if;

  perform public.log_developer_action(
    'user_account_deleted',
    'user',
    target_user_id::text,
    jsonb_build_object(
      'email', target_email,
      'name', target_name,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );

  begin
    perform public.queue_app_email(
      target_email,
      'Grace Connect account deleted',
      'Your Grace Connect account has been deleted by platform support. If this was unexpected, contact Grace Connect support.',
      'Your Grace Connect account has been deleted by platform support. If this was unexpected, contact Grace Connect support.',
      'user',
      target_user_id::text,
      target_user_id,
      jsonb_build_object('type', 'account_deleted', 'reason', nullif(trim(coalesce(p_reason, '')), ''))
    );
  exception when undefined_function then
    null;
  end;

  delete from public.developer_accounts
   where user_id = target_user_id
      or (target_email is not null and lower(email) = lower(target_email));

  delete from public.users
   where id = target_user_id
      or uid = target_user_id::text
      or (target_email is not null and lower(email) = lower(target_email));

  delete from auth.users
   where id = target_user_id;

  return jsonb_build_object('ok', true, 'deleted_user_id', target_user_id, 'email', target_email);
end;
$$;

grant execute on function public.developer_search_users(text, text) to authenticated;
grant execute on function public.developer_get_church_detail(text) to authenticated;
grant execute on function public.developer_approve_member_request(text, text) to authenticated;
grant execute on function public.developer_update_user_access(text, text[], text[], text) to authenticated;
grant execute on function public.developer_delete_user_account(text, text) to authenticated;
