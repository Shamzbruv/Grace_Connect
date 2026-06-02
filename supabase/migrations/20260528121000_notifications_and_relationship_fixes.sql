-- Real in-app notifications and extra hardening for relationship/feed flows.

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  actor_name text not null default 'Grace Connect',
  type text not null,
  title text not null,
  body text not null,
  place_id text,
  entity_table text,
  entity_id text,
  route text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create index if not exists notifications_user_unread_idx
  on public.notifications (user_id, is_read, created_at desc);

alter table public.notifications enable row level security;

drop policy if exists "Users view own notifications" on public.notifications;
create policy "Users view own notifications"
  on public.notifications
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications"
  on public.notifications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users delete own notifications" on public.notifications;
create policy "Users delete own notifications"
  on public.notifications
  for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.display_name_for_user(target_user_id uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select coalesce(nullif("fullName", ''), split_part(email, '@', 1), 'Someone')
  from public.users
  where id = target_user_id
  limit 1;
$$;

create or replace function public.create_notification(
  target_user_id uuid,
  actor_user_id uuid,
  notification_type text,
  notification_title text,
  notification_body text,
  notification_place_id text default null,
  notification_entity_table text default null,
  notification_entity_id text default null,
  notification_route text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  inserted_id uuid;
begin
  if target_user_id is null then
    return null;
  end if;

  if actor_user_id is not null and target_user_id = actor_user_id then
    return null;
  end if;

  insert into public.notifications (
    user_id,
    actor_id,
    actor_name,
    type,
    title,
    body,
    place_id,
    entity_table,
    entity_id,
    route
  )
  values (
    target_user_id,
    actor_user_id,
    coalesce(public.display_name_for_user(actor_user_id), 'Someone'),
    notification_type,
    notification_title,
    notification_body,
    notification_place_id,
    notification_entity_table,
    notification_entity_id,
    notification_route
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

grant execute on function public.create_notification(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;

create or replace function public.notify_on_community_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_author uuid;
  target_place_id text;
begin
  select author_id, place_id
    into target_author, target_place_id
    from public.community_posts
    where id = new.post_id;

  perform public.create_notification(
    target_author,
    new.author_id,
    'comment',
    'New comment',
    coalesce(public.display_name_for_user(new.author_id), 'Someone') ||
      ' commented on your post.',
    target_place_id,
    'community_comments',
    new.id::text,
    '/community'
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_community_comment
  on public.community_comments;
create trigger trg_notify_on_community_comment
  after insert on public.community_comments
  for each row execute function public.notify_on_community_comment();

create or replace function public.notify_on_community_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  liker_id_text text;
  liker_id uuid;
begin
  for liker_id_text in
    select value
    from jsonb_array_elements_text(coalesce(new.likes, '[]'::jsonb)) as value
    except
    select value
    from jsonb_array_elements_text(coalesce(old.likes, '[]'::jsonb)) as value
  loop
    begin
      liker_id := liker_id_text::uuid;
    exception when others then
      liker_id := null;
    end;

    if liker_id is not null then
      perform public.create_notification(
        new.author_id,
        liker_id,
        'like',
        'New like',
        coalesce(public.display_name_for_user(liker_id), 'Someone') ||
          ' liked your post.',
        new.place_id,
        'community_posts',
        new.id::text,
        '/community'
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_community_like
  on public.community_posts;
create trigger trg_notify_on_community_like
  after update of likes on public.community_posts
  for each row
  when (new.likes is distinct from old.likes)
  execute function public.notify_on_community_like();

create or replace function public.relationship_label(relationship_type text)
returns text
language sql
immutable
as $$
  select case relationship_type
    when 'father' then 'father'
    when 'mother' then 'mother'
    when 'husband' then 'husband'
    when 'wife' then 'wife'
    when 'spouse' then 'spouse'
    when 'child' then 'child'
    when 'sibling' then 'sibling'
    when 'guardian' then 'guardian'
    else 'family member'
  end;
$$;

create or replace function public.notify_on_family_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.create_notification(
    new.related_user_id,
    new.requester_id,
    'family_request',
    'Family request',
    coalesce(nullif(new.requester_name, ''), public.display_name_for_user(new.requester_id), 'Someone') ||
      ' listed you as their ' ||
      public.relationship_label(new.relationship_type) ||
      '.',
    new.requester_place_id,
    'family_relationships',
    new.id::text,
    '/profile'
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_family_request
  on public.family_relationships;
create trigger trg_notify_on_family_request
  after insert on public.family_relationships
  for each row execute function public.notify_on_family_request();

create or replace function public.notify_on_family_response()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('accepted', 'declined') and new.status is distinct from old.status then
    perform public.create_notification(
      new.requester_id,
      new.related_user_id,
      'family_response',
      case when new.status = 'accepted' then 'Family request approved' else 'Family request declined' end,
      coalesce(nullif(new.related_name, ''), public.display_name_for_user(new.related_user_id), 'Someone') ||
        case when new.status = 'accepted'
          then ' approved your family request.'
          else ' declined your family request.'
        end,
      new.requester_place_id,
      'family_relationships',
      new.id::text,
      '/profile'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_family_response
  on public.family_relationships;
create trigger trg_notify_on_family_response
  after update of status on public.family_relationships
  for each row execute function public.notify_on_family_response();

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

alter table public.notifications replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'notifications'
    ) then
      execute 'alter publication supabase_realtime add table public.notifications';
    end if;
  end if;
end;
$$;
