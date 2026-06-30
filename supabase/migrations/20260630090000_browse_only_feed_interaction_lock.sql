-- Browse-only accounts may read shared public feed items, but interaction
-- requires an active approved church membership.

drop policy if exists "Members create community comments"
  on public.community_comments;

create policy "Active members create community comments"
  on public.community_comments
  for insert
  to authenticated
  with check (
    author_id::text = auth.uid()::text
    and public.current_active_church_id() is not null
    and exists (
      select 1
      from public.community_posts p
      where p.id = post_id
        and (p.expires_at is null or p.expires_at > now())
        and (
          p.place_id = public.current_active_church_id()
          or p.visible_to_all_churches
        )
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
  current_church_id text := public.current_active_church_id();
  updated_post public.community_posts;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if current_church_id is null then
    raise exception 'Church approval is required before interacting with the feed.';
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
        place_id = current_church_id
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
  current_church_id text := public.current_active_church_id();
  updated_story public.community_stories;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  if current_church_id is null then
    raise exception 'Church approval is required before interacting with the feed.';
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
        church_id = current_church_id
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
