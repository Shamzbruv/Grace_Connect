-- Repair a production function that compared UUID feed authors to text. The
-- mismatch made profile-photo propagation fail after a member changed their
-- picture, leaving stale avatars throughout the community experience.

create or replace function public.sync_user_profile_photo_references(
  photo_url text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.community_posts
     set author_photo = photo_url
   where author_id = auth.uid();

  update public.community_stories
     set author_photo = photo_url
   where author_id = auth.uid()::text;

  update public.community_comments
     set author_photo = photo_url
   where author_id = auth.uid();
end;
$$;

revoke all on function public.sync_user_profile_photo_references(text)
  from public, anon;
grant execute on function public.sync_user_profile_photo_references(text)
  to authenticated;
