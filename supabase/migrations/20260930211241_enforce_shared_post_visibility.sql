-- An old public-role SELECT USING(true) bypassed the newer church policy.
-- A single permission predicate protects feed reads and shared message previews.
create or replace function public.can_read_community_post(p_post_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
select auth.uid() is not null and exists (
  select 1 from public.community_posts p where p.id=p_post_id
  and (p.expires_at is null or p.expires_at>now())
  and (
    p.author_id=auth.uid()
    or (p.scope<>'circle' and (
      p.visible_to_all_churches or p.scope in ('global','discover','public')
      or p.place_id=public.viewer_effective_church_id()
    ))
  )
  and not exists (select 1 from public.user_blocks b
    where (b.blocker_id=auth.uid()::text and b.blocked_user_id=p.author_id::text)
       or (b.blocker_id=p.author_id::text and b.blocked_user_id=auth.uid()::text))
) $$;
revoke all on function public.can_read_community_post(uuid) from public, anon;
grant execute on function public.can_read_community_post(uuid) to authenticated;
drop policy if exists "Users can view posts from their church" on public.community_posts;
drop policy if exists "Members view church posts" on public.community_posts;
drop policy if exists "Authenticated users view visible community posts" on public.community_posts;
create policy "Authenticated users view visible community posts" on public.community_posts
for select to authenticated using (public.can_read_community_post(id));
