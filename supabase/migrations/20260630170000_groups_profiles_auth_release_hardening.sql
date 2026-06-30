-- Release 1.0.14 beta hardening:
-- - Study group join requests, group admin promotion, and message avatars.
-- - Member/pastor profile fields used by the app profile screens.
-- - Public church directory details for website search cards.

alter table public.study_groups
  add column if not exists "pendingMemberIds" text[] not null default '{}'::text[];

alter table public.group_messages
  add column if not exists "senderPhotoUrl" text;

alter table public.users
  add column if not exists "dateOfBirth" date,
  add column if not exists gender text,
  add column if not exists occupation text,
  add column if not exists "emergencyContactName" text,
  add column if not exists "emergencyContactPhone" text,
  add column if not exists "pastoralTitle" text,
  add column if not exists "pastorPublicBio" text,
  add column if not exists "ordinationDate" date,
  add column if not exists "publicEmail" text,
  add column if not exists "publicPhone" text,
  add column if not exists "showPastorPublicContact" boolean not null default true;

drop function if exists public.join_study_group(text);
create function public.join_study_group(target_group_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if actor_id = target_group."leaderId"
     or actor_id = any(coalesce(target_group."adminIds", '{}'::text[]))
     or actor_id = any(coalesce(target_group."memberIds", '{}'::text[])) then
    return 'active';
  end if;

  if target_group."requireJoinApproval" then
    update public.study_groups
      set "pendingMemberIds" = (
        select array(
          select distinct member_id
          from unnest(coalesce("pendingMemberIds", '{}'::text[]) || actor_id)
            as member(member_id)
          where member_id is not null and member_id <> ''
        )
      )
      where id = target_group_id;
    return 'pending';
  end if;

  update public.study_groups
    set "memberIds" = (
      select array(
        select distinct member_id
        from unnest(coalesce("memberIds", '{}'::text[]) || actor_id)
          as member(member_id)
        where member_id is not null and member_id <> ''
      )
    ),
        "pendingMemberIds" = array_remove(
          coalesce("pendingMemberIds", '{}'::text[]),
          actor_id
        )
    where id = target_group_id;

  return 'active';
end;
$$;

create or replace function public.leave_study_group(target_group_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if actor_id = target_group."leaderId" then
    raise exception 'The group leader cannot leave their own group';
  end if;

  update public.study_groups
    set "memberIds" = array_remove(
      coalesce("memberIds", '{}'::text[]),
      actor_id
    ),
        "adminIds" = array_remove(
      coalesce("adminIds", '{}'::text[]),
      actor_id
    ),
        "pendingMemberIds" = array_remove(
      coalesce("pendingMemberIds", '{}'::text[]),
      actor_id
    )
    where id = target_group_id;
end;
$$;

create or replace function public.approve_study_group_member(
  target_group_id text,
  target_user_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
  clean_user_id text := nullif(trim(coalesce(target_user_id, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if clean_user_id is null then
    raise exception 'Member is required';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if actor_id <> target_group."leaderId"
     and actor_id <> all(coalesce(target_group."adminIds", '{}'::text[])) then
    raise exception 'Only a group admin can approve group requests';
  end if;

  update public.study_groups
    set "memberIds" = (
      select array(
        select distinct member_id
        from unnest(coalesce("memberIds", '{}'::text[]) || clean_user_id)
          as member(member_id)
        where member_id is not null and member_id <> ''
      )
    ),
        "pendingMemberIds" = array_remove(
          coalesce("pendingMemberIds", '{}'::text[]),
          clean_user_id
        )
    where id = target_group_id;

  begin
    perform public.create_notification(
      clean_user_id::uuid,
      actor_id::uuid,
      'group_membership_approved',
      'Group request approved',
      'Your request to join ' || coalesce(target_group.name, 'this group') || ' was approved.',
      target_group."churchId",
      'study_groups',
      target_group_id,
      '/study_groups'
    );
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'status', 'active');
end;
$$;

create or replace function public.set_study_group_admin(
  target_group_id text,
  target_user_id text,
  make_admin boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group public.study_groups;
  actor_id text := auth.uid()::text;
  clean_user_id text := nullif(trim(coalesce(target_user_id, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if clean_user_id is null then
    raise exception 'Member is required';
  end if;

  select *
    into target_group
    from public.study_groups
    where id = target_group_id
      and "churchId" = public.get_church_id()
    for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if actor_id <> target_group."leaderId"
     and actor_id <> all(coalesce(target_group."adminIds", '{}'::text[])) then
    raise exception 'Only a group admin can manage group admins';
  end if;

  if clean_user_id = target_group."leaderId" then
    return jsonb_build_object('ok', true, 'admin', true);
  end if;

  if clean_user_id <> any(coalesce(target_group."memberIds", '{}'::text[])) then
    raise exception 'Only group members can be made admins';
  end if;

  if make_admin then
    update public.study_groups
      set "adminIds" = (
        select array(
          select distinct admin_id
          from unnest(coalesce("adminIds", '{}'::text[]) || clean_user_id)
            as admin(admin_id)
          where admin_id is not null and admin_id <> ''
        )
      )
      where id = target_group_id;
  else
    update public.study_groups
      set "adminIds" = array_remove(
        coalesce("adminIds", '{}'::text[]),
        clean_user_id
      )
      where id = target_group_id;
  end if;

  return jsonb_build_object('ok', true, 'admin', make_admin);
end;
$$;

drop function if exists public.get_public_church_directory(text);
create or replace function public.get_public_church_directory(search_query text default null)
returns table (
  id text,
  "placeId" text,
  name text,
  address text,
  parish text,
  denomination text,
  about text,
  founded_year integer,
  contact_email text,
  contact_phone text,
  website_url text,
  service_times_note text,
  lead_pastor text,
  member_count bigint
)
language sql
security definer
set search_path to 'public'
as $$
  select
    coalesce(c.id::text, c."placeId") as id,
    coalesce(c."placeId", c.id::text) as "placeId",
    coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId", c.id::text)::text as name,
    coalesce(c.address, '')::text as address,
    coalesce(c.parish, '')::text as parish,
    coalesce(c.denomination_label, c.denomination, '')::text as denomination,
    coalesce(c.about, '')::text as about,
    c.founded_year,
    coalesce(c.contact_email, '')::text as contact_email,
    coalesce(c.contact_phone, '')::text as contact_phone,
    coalesce(c.website_url, '')::text as website_url,
    coalesce(c.service_times_note, '')::text as service_times_note,
    coalesce(pastor.full_name, '')::text as lead_pastor,
    coalesce(member_counts.member_count, 0)::bigint as member_count
  from public.churches c
  left join lateral (
    select u."fullName" as full_name
    from public.church_memberships cm
    join public.users u on u.id = cm.user_id or u.uid = cm.user_id::text
    left join public.church_member_roles cmr
      on cmr.membership_id = cm.id
     and cmr.revoked_at is null
    where cm.church_id in (c.id::text, c."placeId"::text)
      and cm.membership_status = 'active'
      and (
        public.normalize_role_name(cmr.role_name) in ('pastor', 'senior_pastor')
        or exists (
          select 1
          from unnest(coalesce(u.roles, '{}'::text[])) as user_role(role_name)
          where public.normalize_role_name(user_role.role_name) in ('pastor', 'senior_pastor')
        )
      )
    order by
      case when public.normalize_role_name(cmr.role_name) = 'senior_pastor' then 0 else 1 end,
      cm.reviewed_at asc nulls last
    limit 1
  ) pastor on true
  left join lateral (
    select count(*) as member_count
    from public.church_memberships cm
    where cm.church_id in (c.id::text, c."placeId"::text)
      and cm.membership_status = 'active'
  ) member_counts on true
  where (
      (c.church_status = 'approved' and coalesce(c.public_visibility, true) = true)
      or coalesce(c.status, '') in ('active', 'verified')
    )
    and (
      nullif(trim(coalesce(search_query, '')), '') is null
      or coalesce(c.display_name, c.name, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c."placeId", '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.address, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.parish, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.denomination_label, c.denomination, '') ilike '%' || trim(search_query) || '%'
    )
  order by name
  limit 25;
$$;

grant execute on function public.join_study_group(text) to authenticated;
grant execute on function public.leave_study_group(text) to authenticated;
grant execute on function public.approve_study_group_member(text, text) to authenticated;
grant execute on function public.set_study_group_admin(text, text, boolean) to authenticated;
grant execute on function public.get_public_church_directory(text) to anon, authenticated;
