-- Cross-church sharing controls for events, community posts, and statuses.
-- Private church content stays church-only unless the creator opts in.

alter table public.events
  add column if not exists visible_to_all_churches boolean not null default false;

alter table public.community_posts
  add column if not exists visible_to_all_churches boolean not null default false;

alter table public.community_stories
  add column if not exists visible_to_all_churches boolean not null default false;

create index if not exists events_shared_visibility_idx
  on public.events (visible_to_all_churches, date);

create index if not exists community_posts_shared_visibility_idx
  on public.community_posts (visible_to_all_churches, created_at desc);

create index if not exists community_stories_shared_visibility_idx
  on public.community_stories (visible_to_all_churches, expires_at desc, created_at desc);

alter table public.events enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;
alter table public.community_stories enable row level security;

drop policy if exists "Members view own or shared events" on public.events;
create policy "Members view own or shared events"
  on public.events
  for select
  to authenticated
  using (
    "churchId" = public.get_church_id()
    or visible_to_all_churches
  );

drop policy if exists "Authenticated users view active community posts"
  on public.community_posts;
drop policy if exists "Members view own or shared community posts"
  on public.community_posts;
create policy "Members view own or shared community posts"
  on public.community_posts
  for select
  to authenticated
  using (
    (expires_at is null or expires_at > now())
    and (
      place_id = public.get_church_id()
      or visible_to_all_churches
    )
  );

drop policy if exists "Members create community comments"
  on public.community_comments;
create policy "Members create community comments"
  on public.community_comments
  for insert
  to authenticated
  with check (
    author_id::text = auth.uid()::text
    and exists (
      select 1
      from public.community_posts p
      where p.id = post_id
        and (p.expires_at is null or p.expires_at > now())
        and (
          p.place_id = public.get_church_id()
          or p.visible_to_all_churches
        )
    )
  );

drop policy if exists "Authenticated users view community comments"
  on public.community_comments;
create policy "Authenticated users view community comments"
  on public.community_comments
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.community_posts p
      where p.id = post_id
        and (p.expires_at is null or p.expires_at > now())
        and (
          p.place_id = public.get_church_id()
          or p.visible_to_all_churches
        )
    )
  );

drop policy if exists "Church members view active stories"
  on public.community_stories;
drop policy if exists "Members view own or shared active stories"
  on public.community_stories;
create policy "Members view own or shared active stories"
  on public.community_stories
  for select
  to authenticated
  using (
    expires_at > now()
    and (
      church_id = public.get_church_id()
      or visible_to_all_churches
    )
  );

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
      and (expires_at is null or expires_at > now())
      and (
        place_id = public.get_church_id()
        or visible_to_all_churches
      )
    returning * into updated_post;

  if not found then
    raise exception 'Post not found or unavailable';
  end if;

  return updated_post;
end;
$$;

grant execute on function public.toggle_community_post_like(uuid)
  to authenticated;

create or replace function public.toggle_community_story_like(target_story_id uuid)
returns public.community_stories
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  updated_story public.community_stories;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  update public.community_stories
    set likes = case
      when actor_uid = any(coalesce(likes, '{}'::text[]))
        then array_remove(coalesce(likes, '{}'::text[]), actor_uid)
      else array_append(coalesce(likes, '{}'::text[]), actor_uid)
    end
    where id = target_story_id
      and expires_at > now()
      and (
        church_id = public.get_church_id()
        or visible_to_all_churches
      )
    returning * into updated_story;

  if updated_story.id is null then
    raise exception 'Status not found';
  end if;

  return updated_story;
end;
$$;

grant execute on function public.toggle_community_story_like(uuid)
  to authenticated;

create or replace function public.rsvp_event(target_event_id text, is_joining boolean)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  current_user_id text := auth.uid()::text;
  actor_church_id text := public.get_church_id();
  target_church_id text;
  target_visible_to_all boolean;
  current_attendees text[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select "churchId", coalesce(visible_to_all_churches, false), coalesce(attendees, '{}'::text[])
    into target_church_id, target_visible_to_all, current_attendees
  from public.events
  where id = target_event_id;

  if target_church_id is null then
    raise exception 'Event not found';
  end if;

  if target_church_id <> actor_church_id and not target_visible_to_all then
    raise exception 'You cannot RSVP to a private event outside your church';
  end if;

  update public.events
  set attendees = case
    when is_joining then (
      select array_agg(distinct attendee)
      from unnest(current_attendees || current_user_id) as attendee
    )
    else array_remove(current_attendees, current_user_id)
  end
  where id = target_event_id;
end;
$$;

grant execute on function public.rsvp_event(text, boolean) to authenticated;

create or replace function public.get_event_rsvp_details(target_event_id text)
returns table (
  user_id text,
  full_name text,
  email text,
  church_id text,
  church_name text,
  is_other_church boolean
)
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_church_id text := public.get_church_id();
  target_church_id text;
  target_ministry_id uuid;
  current_attendees text[];
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select e."churchId", e.ministry_id, coalesce(e.attendees, '{}'::text[])
    into target_church_id, target_ministry_id, current_attendees
  from public.events e
  where e.id = target_event_id;

  if target_church_id is null then
    raise exception 'Event not found';
  end if;

  if target_church_id <> actor_church_id then
    raise exception 'Only the host church can view RSVP details';
  end if;

  if not (
    public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Church Admin',
      'Admin',
      'Administrator',
      'Secretary',
      'Church Secretary',
      'Event Coordinator',
      'Ministry Leader'
    ])
    or public.has_app_privilege('createEvents')
    or (
      target_ministry_id is not null
      and public.is_ministry_manager(target_church_id, target_ministry_id, 'events')
    )
  ) then
    raise exception 'You do not have permission to view RSVP details';
  end if;

  return query
    select
      coalesce(u.uid, u.id::text) as user_id,
      coalesce(nullif(u."fullName", ''), nullif(u.email, ''), 'Member') as full_name,
      coalesce(u.email, '') as email,
      coalesce(u."placeId", '') as church_id,
      coalesce(nullif(c.name, ''), nullif(u."placeName", ''), u."placeId", 'Church') as church_name,
      coalesce(u."placeId", '') <> target_church_id as is_other_church
    from unnest(current_attendees) as attendee_id
    join public.users u
      on u.uid = attendee_id
      or u.id::text = attendee_id
    left join public.churches c
      on c.id = u."placeId"
      or c."placeId" = u."placeId"
    order by is_other_church, full_name;
end;
$$;

grant execute on function public.get_event_rsvp_details(text) to authenticated;
