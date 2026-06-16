alter table public.users
  add column if not exists "showContactInfo" boolean not null default true,
  add column if not exists "showFamilyTree" boolean not null default true,
  add column if not exists "showFamilyRelationshipTypes" boolean not null default true,
  add column if not exists "allowFamilyLinkRequests" boolean not null default true,
  add column if not exists "familyTreeVisibility" text not null default 'church';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'users_family_tree_visibility_check'
  ) then
    alter table public.users
      add constraint users_family_tree_visibility_check
      check ("familyTreeVisibility" in ('church', 'family', 'private'));
  end if;
end;
$$;

alter table public.family_relationships
  drop constraint if exists family_relationships_relationship_type_check;

alter table public.family_relationships
  add constraint family_relationships_relationship_type_check
  check (
    relationship_type in (
      'father',
      'mother',
      'parent',
      'son',
      'daughter',
      'child',
      'brother',
      'sister',
      'sibling',
      'husband',
      'wife',
      'spouse',
      'grandfather',
      'grandmother',
      'grandparent',
      'grandson',
      'granddaughter',
      'grandchild',
      'uncle',
      'aunt',
      'nephew',
      'niece',
      'cousin',
      'father_in_law',
      'mother_in_law',
      'brother_in_law',
      'sister_in_law',
      'son_in_law',
      'daughter_in_law',
      'step_father',
      'step_mother',
      'step_parent',
      'step_son',
      'step_daughter',
      'step_child',
      'adoptive_father',
      'adoptive_mother',
      'adoptive_parent',
      'adopted_son',
      'adopted_daughter',
      'adopted_child',
      'guardian',
      'ward',
      'godfather',
      'godmother',
      'godparent',
      'godson',
      'goddaughter',
      'godchild',
      'spiritual_father',
      'spiritual_mother',
      'spiritual_parent',
      'mentor',
      'mentee',
      'other'
    )
  );

create or replace function public.relationship_label(relationship_type text)
returns text
language sql
immutable
as $$
  select case relationship_type
    when 'father' then 'father'
    when 'mother' then 'mother'
    when 'parent' then 'parent'
    when 'son' then 'son'
    when 'daughter' then 'daughter'
    when 'child' then 'child'
    when 'brother' then 'brother'
    when 'sister' then 'sister'
    when 'sibling' then 'sibling'
    when 'husband' then 'husband'
    when 'wife' then 'wife'
    when 'spouse' then 'spouse'
    when 'grandfather' then 'grandfather'
    when 'grandmother' then 'grandmother'
    when 'grandparent' then 'grandparent'
    when 'grandson' then 'grandson'
    when 'granddaughter' then 'granddaughter'
    when 'grandchild' then 'grandchild'
    when 'uncle' then 'uncle'
    when 'aunt' then 'aunt'
    when 'nephew' then 'nephew'
    when 'niece' then 'niece'
    when 'cousin' then 'cousin'
    when 'father_in_law' then 'father-in-law'
    when 'mother_in_law' then 'mother-in-law'
    when 'brother_in_law' then 'brother-in-law'
    when 'sister_in_law' then 'sister-in-law'
    when 'son_in_law' then 'son-in-law'
    when 'daughter_in_law' then 'daughter-in-law'
    when 'step_father' then 'stepfather'
    when 'step_mother' then 'stepmother'
    when 'step_parent' then 'step-parent'
    when 'step_son' then 'stepson'
    when 'step_daughter' then 'stepdaughter'
    when 'step_child' then 'stepchild'
    when 'adoptive_father' then 'adoptive father'
    when 'adoptive_mother' then 'adoptive mother'
    when 'adoptive_parent' then 'adoptive parent'
    when 'adopted_son' then 'adopted son'
    when 'adopted_daughter' then 'adopted daughter'
    when 'adopted_child' then 'adopted child'
    when 'guardian' then 'guardian'
    when 'ward' then 'ward'
    when 'godfather' then 'godfather'
    when 'godmother' then 'godmother'
    when 'godparent' then 'godparent'
    when 'godson' then 'godson'
    when 'goddaughter' then 'goddaughter'
    when 'godchild' then 'godchild'
    when 'spiritual_father' then 'spiritual father'
    when 'spiritual_mother' then 'spiritual mother'
    when 'spiritual_parent' then 'spiritual parent'
    when 'mentor' then 'mentor'
    when 'mentee' then 'mentee'
    else 'family member'
  end;
$$;

create or replace function public.request_family_relationship(
  target_user_id uuid,
  requested_relationship_type text,
  request_note text default ''
)
returns public.family_relationships
language plpgsql
security definer
set search_path = public
as $$
declare
  requester public.users;
  related public.users;
  inserted_relationship public.family_relationships;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if auth.uid() = target_user_id then
    raise exception 'You cannot connect yourself as family';
  end if;

  select *
    into requester
    from public.users
    where id = auth.uid()
    limit 1;

  select *
    into related
    from public.users
    where id = target_user_id
    limit 1;

  if requester.id is null or related.id is null then
    raise exception 'Member profile not found';
  end if;

  if coalesce(related."allowFamilyLinkRequests", true) = false then
    raise exception 'This member is not accepting family link requests right now';
  end if;

  if coalesce(requester."placeId", '') = ''
     or requester."placeId" is distinct from related."placeId" then
    raise exception 'Family links can only be requested inside the same church';
  end if;

  insert into public.family_relationships (
    requester_id,
    related_user_id,
    requester_name,
    related_name,
    relationship_type,
    requester_place_id,
    related_place_id,
    status,
    note
  )
  values (
    requester.id,
    related.id,
    coalesce(nullif(requester."fullName", ''), requester.email),
    coalesce(nullif(related."fullName", ''), related.email),
    requested_relationship_type,
    requester."placeId",
    related."placeId",
    'pending',
    nullif(trim(request_note), '')
  )
  returning * into inserted_relationship;

  return inserted_relationship;
exception
  when unique_violation then
    raise exception 'There is already an active request for this family link';
end;
$$;

grant execute on function public.request_family_relationship(uuid, text, text)
  to authenticated;

create or replace function public.get_visible_family_relationships(
  profile_user_id uuid
)
returns table (
  id uuid,
  requester_id uuid,
  related_user_id uuid,
  requester_name text,
  related_name text,
  relationship_type text,
  requester_place_id text,
  related_place_id text,
  status text,
  note text,
  requested_at timestamptz,
  responded_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer public.users;
  profile_owner public.users;
  visibility text;
begin
  if auth.uid() is null then
    return;
  end if;

  select u.*
    into viewer
    from public.users u
    where u.id = auth.uid()
    limit 1;

  select u.*
    into profile_owner
    from public.users u
    where u.id = profile_user_id
    limit 1;

  if viewer.id is null or profile_owner.id is null then
    return;
  end if;

  if coalesce(viewer."placeId", '') = ''
     or viewer."placeId" is distinct from profile_owner."placeId" then
    return;
  end if;

  if viewer.id <> profile_owner.id then
    if coalesce(profile_owner."isProfilePrivate", false) then
      return;
    end if;

    if coalesce(profile_owner."showFamilyTree", true) = false then
      return;
    end if;

    visibility := coalesce(profile_owner."familyTreeVisibility", 'church');

    if visibility = 'private' then
      return;
    end if;

    if visibility = 'family' and not exists (
      select 1
      from public.family_relationships existing
      where existing.status = 'accepted'
        and (
          (existing.requester_id = profile_owner.id and existing.related_user_id = viewer.id)
          or
          (existing.related_user_id = profile_owner.id and existing.requester_id = viewer.id)
        )
    ) then
      return;
    end if;
  end if;

  return query
    select
      rel.id,
      rel.requester_id,
      rel.related_user_id,
      rel.requester_name,
      rel.related_name,
      rel.relationship_type,
      rel.requester_place_id,
      rel.related_place_id,
      rel.status,
      rel.note,
      rel.requested_at,
      rel.responded_at
    from public.family_relationships rel
    join public.users requester on requester.id = rel.requester_id
    join public.users related on related.id = rel.related_user_id
    where rel.status = 'accepted'
      and (rel.requester_id = profile_owner.id or rel.related_user_id = profile_owner.id)
      and rel.requester_place_id = profile_owner."placeId"
      and rel.related_place_id = profile_owner."placeId"
      and (
        viewer.id = profile_owner.id
        or (
          coalesce(requester."showFamilyTree", true)
          and coalesce(related."showFamilyTree", true)
        )
      )
    order by rel.requested_at desc;
end;
$$;

grant execute on function public.get_visible_family_relationships(uuid)
  to authenticated;
