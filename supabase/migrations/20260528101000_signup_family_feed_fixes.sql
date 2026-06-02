-- Grace Connect beta hardening:
-- - create user/church rows from auth signup metadata so RLS cannot block signup
-- - add family relationship requests with approval
-- - make comments counts deterministic
-- - make feed like updates atomic
-- - publish feed/family tables to Supabase Realtime

create extension if not exists pgcrypto;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  profile_roles text[] := array['Member'];
  profile_place_id text := nullif(coalesce(meta->>'placeId', meta->>'churchId'), '');
  profile_place_name text := nullif(coalesce(meta->>'placeName', meta->>'churchName'), '');
  profile_phone text := nullif(coalesce(meta->>'phone', meta->>'phoneNumber'), '');
  profile_join_date timestamptz := now();
  creates_church boolean := false;
begin
  if jsonb_typeof(meta->'roles') = 'array' then
    select coalesce(array_agg(value), array['Member'])
      into profile_roles
      from jsonb_array_elements_text(meta->'roles') as roles(value)
      where nullif(trim(value), '') is not null;
  elsif nullif(meta->>'role', '') is not null then
    profile_roles := array[meta->>'role'];
  end if;

  if nullif(meta->>'joinDate', '') is not null then
    begin
      profile_join_date := (meta->>'joinDate')::timestamptz;
    exception when others then
      profile_join_date := now();
    end;
  end if;

  select exists (
    select 1
    from unnest(profile_roles) as role_name
    where lower(role_name) in ('admin', 'church admin', 'pastor')
  )
    into creates_church;

  if profile_place_id is null and creates_church then
    profile_place_id := 'church_' || replace(new.id::text, '-', '');
  end if;

  if profile_place_name is null and creates_church then
    profile_place_name := 'New Church';
  end if;

  if creates_church and profile_place_id is not null then
    insert into public.churches (
      id,
      "placeId",
      name,
      address,
      denomination,
      "ownerUserId",
      timezone,
      status,
      "createdAt"
    )
    values (
      profile_place_id,
      profile_place_id,
      coalesce(profile_place_name, 'New Church'),
      nullif(meta->>'address', ''),
      nullif(meta->>'denomination', ''),
      new.id::text,
      coalesce(nullif(meta->>'timezone', ''), 'UTC'),
      'active',
      now()
    )
    on conflict ("placeId") do update
      set "ownerUserId" = excluded."ownerUserId",
          status = 'active',
          name = coalesce(nullif(excluded.name, ''), public.churches.name),
          address = coalesce(excluded.address, public.churches.address),
          denomination = coalesce(
            excluded.denomination,
            public.churches.denomination
          );
  end if;

  insert into public.users (
    id,
    uid,
    email,
    "fullName",
    phone,
    "placeId",
    "placeName",
    roles,
    "joinDate",
    "photoUrl",
    bio,
    "isDeveloper",
    "accountState"
  )
  values (
    new.id,
    new.id::text,
    coalesce(new.email, ''),
    coalesce(
      nullif(meta->>'fullName', ''),
      nullif(meta->>'full_name', ''),
      nullif(meta->>'name', ''),
      split_part(coalesce(new.email, 'Member'), '@', 1)
    ),
    profile_phone,
    profile_place_id,
    profile_place_name,
    profile_roles,
    profile_join_date,
    coalesce(nullif(meta->>'avatar_url', ''), ''),
    coalesce(nullif(meta->>'bio', ''), ''),
    false,
    coalesce(nullif(meta->>'accountState', ''), 'active')
  )
  on conflict (uid) do update
    set email = excluded.email,
        "fullName" = coalesce(nullif(excluded."fullName", ''), public.users."fullName"),
        phone = coalesce(excluded.phone, public.users.phone),
        "placeId" = coalesce(excluded."placeId", public.users."placeId"),
        "placeName" = coalesce(excluded."placeName", public.users."placeName"),
        roles = case
          when array_length(excluded.roles, 1) is null then public.users.roles
          else excluded.roles
        end,
        "joinDate" = coalesce(public.users."joinDate", excluded."joinDate"),
        "photoUrl" = coalesce(nullif(excluded."photoUrl", ''), public.users."photoUrl"),
        bio = coalesce(nullif(excluded.bio, ''), public.users.bio),
        "accountState" = coalesce(excluded."accountState", public.users."accountState");

  if creates_church and profile_place_id is not null then
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'users'
        and column_name = 'approvalStatus'
    ) then
      execute
        'update public.users
           set "accountState" = ''active'',
               "approvalStatus" = ''pending''
         where "placeId" = $1
           and "accountState" = ''awaiting_church_signup'''
      using profile_place_id;
    else
      update public.users
        set "accountState" = 'active'
        where "placeId" = profile_place_id
          and "accountState" = 'awaiting_church_signup';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

drop policy if exists "Users insert own profile by uid" on public.users;
create policy "Users insert own profile by uid"
  on public.users
  for insert
  to authenticated
  with check (auth.uid() = id or auth.uid()::text = uid);

alter table public.churches
  alter column id set default ('church_' || replace(gen_random_uuid()::text, '-', ''));

create table if not exists public.family_relationships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  related_user_id uuid not null references auth.users(id) on delete cascade,
  requester_name text not null default '',
  related_name text not null default '',
  relationship_type text not null check (
    relationship_type in (
      'father',
      'mother',
      'husband',
      'wife',
      'spouse',
      'child',
      'sibling',
      'guardian',
      'other'
    )
  ),
  requester_place_id text not null,
  related_place_id text not null,
  status text not null default 'pending' check (
    status in ('pending', 'accepted', 'declined', 'cancelled')
  ),
  note text,
  requested_at timestamptz not null default now(),
  responded_at timestamptz
);

create index if not exists family_relationships_requester_idx
  on public.family_relationships (requester_id, status);

create index if not exists family_relationships_related_idx
  on public.family_relationships (related_user_id, status);

create index if not exists family_relationships_church_idx
  on public.family_relationships (requester_place_id, related_place_id);

create unique index if not exists family_relationships_active_unique_idx
  on public.family_relationships (
    requester_id,
    related_user_id,
    relationship_type
  )
  where status in ('pending', 'accepted');

alter table public.family_relationships enable row level security;

drop policy if exists "Family members can view own relationship requests"
  on public.family_relationships;
create policy "Family members can view own relationship requests"
  on public.family_relationships
  for select
  to authenticated
  using (auth.uid() = requester_id or auth.uid() = related_user_id);

drop policy if exists "Members can request family links in their church"
  on public.family_relationships;
create policy "Members can request family links in their church"
  on public.family_relationships
  for insert
  to authenticated
  with check (
    auth.uid() = requester_id
    and requester_id <> related_user_id
    and requester_place_id = related_place_id
    and requester_place_id = public.get_church_id()
    and exists (
      select 1
      from public.users requester
      where requester.id = requester_id
        and requester."placeId" = requester_place_id
    )
    and exists (
      select 1
      from public.users related
      where related.id = related_user_id
        and related."placeId" = related_place_id
    )
  );

drop policy if exists "Requesters can cancel pending family links"
  on public.family_relationships;
create policy "Requesters can cancel pending family links"
  on public.family_relationships
  for update
  to authenticated
  using (auth.uid() = requester_id and status = 'pending')
  with check (auth.uid() = requester_id and status = 'cancelled');

create or replace function public.respond_to_family_relationship(
  relationship_id uuid,
  approve boolean
)
returns public.family_relationships
language plpgsql
security definer
set search_path = public
as $$
declare
  rel public.family_relationships;
  next_status text := case when approve then 'accepted' else 'declined' end;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into rel
    from public.family_relationships
    where id = relationship_id
      and related_user_id = auth.uid()
      and status = 'pending'
    for update;

  if not found then
    raise exception 'Family request not found or already handled';
  end if;

  update public.family_relationships
    set status = next_status,
        responded_at = now()
    where id = relationship_id
    returning * into rel;

  if approve then
    if rel.relationship_type = 'father' then
      update public.users
        set "fatherId" = rel.related_user_id::text
        where id = rel.requester_id;
    elsif rel.relationship_type = 'mother' then
      update public.users
        set "motherId" = rel.related_user_id::text
        where id = rel.requester_id;
    elsif rel.relationship_type in ('husband', 'wife', 'spouse') then
      update public.users
        set "spouseId" = rel.related_user_id::text
        where id = rel.requester_id;

      update public.users
        set "spouseId" = rel.requester_id::text
        where id = rel.related_user_id;
    elsif rel.relationship_type = 'child' then
      update public.users
        set "childrenIds" = (
          select array(
            select distinct child_id
            from unnest(coalesce("childrenIds", '{}'::text[]) || rel.related_user_id::text) as child_id
            where child_id is not null and child_id <> ''
          )
        )
        where id = rel.requester_id;
    end if;
  end if;

  return rel;
end;
$$;

grant execute on function public.respond_to_family_relationship(uuid, boolean)
  to authenticated;

create or replace function public.toggle_community_post_like(post_id uuid)
returns public.community_posts
language plpgsql
security definer
set search_path = public
as $$
declare
  current_uid text := auth.uid()::text;
  updated_post public.community_posts;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.community_posts
    set likes = case
      when coalesce(likes, '[]'::jsonb) ? current_uid
        then coalesce(likes, '[]'::jsonb) - current_uid
      else coalesce(likes, '[]'::jsonb) || jsonb_build_array(current_uid)
    end
    where id = post_id
      and exists (
        select 1
        from public.users u
        where u.id = auth.uid()
          and u."placeId" = public.community_posts.place_id
      )
    returning * into updated_post;

  if not found then
    raise exception 'Post not found or not available to this church';
  end if;

  return updated_post;
end;
$$;

grant execute on function public.toggle_community_post_like(uuid)
  to authenticated;

drop trigger if exists on_comment_added on public.community_comments;
drop trigger if exists on_comment_deleted on public.community_comments;
drop trigger if exists trg_update_comments_count on public.community_comments;
drop trigger if exists trg_sync_comments_count on public.community_comments;

create or replace function public.sync_comments_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post_id uuid := coalesce(new.post_id, old.post_id);
begin
  update public.community_posts
    set comments_count = (
      select count(*)::integer
      from public.community_comments
      where post_id = target_post_id
    )
    where id = target_post_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_sync_comments_count
  after insert or delete on public.community_comments
  for each row execute function public.sync_comments_count();

update public.community_posts p
  set comments_count = counts.total
  from (
    select post_id, count(*)::integer as total
    from public.community_comments
    group by post_id
  ) counts
  where counts.post_id = p.id;

update public.community_posts
  set comments_count = 0
  where id not in (select distinct post_id from public.community_comments);

alter table public.community_posts replica identity full;
alter table public.community_comments replica identity full;
alter table public.family_relationships replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'community_posts'
    ) then
      execute 'alter publication supabase_realtime add table public.community_posts';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'community_comments'
    ) then
      execute 'alter publication supabase_realtime add table public.community_comments';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'family_relationships'
    ) then
      execute 'alter publication supabase_realtime add table public.family_relationships';
    end if;
  end if;
end;
$$;
