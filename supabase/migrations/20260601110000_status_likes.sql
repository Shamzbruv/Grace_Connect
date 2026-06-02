alter table public.community_stories
  add column if not exists likes text[] not null default '{}';

update public.community_stories
  set likes = '{}'
  where likes is null;

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
      and church_id = public.get_church_id()
      and expires_at > now()
    returning * into updated_story;

  if updated_story.id is null then
    raise exception 'Status not found';
  end if;

  return updated_story;
end;
$$;

grant execute on function public.toggle_community_story_like(uuid)
  to authenticated;
