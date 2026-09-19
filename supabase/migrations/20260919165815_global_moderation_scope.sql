-- Moderation for global content (Reel Grace).
--
-- Reporting and blocking were church-scoped: both tables require church_id
-- NOT NULL and both INSERT policies require church_id = get_church_id(). For
-- a viewer with no church that predicate is never true, so the insert was
-- rejected -- and the Dart layer returned early without surfacing anything.
-- Report and Block were therefore silent no-ops on exactly the surface that
-- most needs them: a public video feed where the creator may be a stranger
-- in another church, or in none.
--
-- Rather than make church_id nullable and disturb every existing church
-- moderation policy, global rows carry an explicit sentinel scope. Church
-- moderation behaviour is unchanged.

create or replace function public.grace_connect_global_scope_id()
returns text language sql immutable set search_path = ''
as $$ select 'grace_connect_global'::text $$;
grant execute on function public.grace_connect_global_scope_id() to authenticated;

-- Reports: keep the church rule, add the global one.
drop policy if exists "Users create reports" on public.content_reports;
create policy "Users create reports" on public.content_reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())::text
    and (
      church_id = public.get_church_id()
      or church_id = public.grace_connect_global_scope_id()
    )
  );

-- A reporter can always see their own report; church leaders see their
-- church's. Global reports are reviewed by developers, not by one church's
-- leadership, so they are deliberately not exposed to church roles here.
drop policy if exists "Users view own reports" on public.content_reports;
create policy "Users view own reports" on public.content_reports
  for select to authenticated
  using (
    reporter_id = (select auth.uid())::text
    or (
      church_id = public.get_church_id()
      and church_id <> public.grace_connect_global_scope_id()
      and public.has_any_role(array['Pastor','Senior Pastor','Secretary'])
    )
  );

-- Blocks are a relationship between two people; church_id only partitions
-- them. A block must be possible regardless of shared church, otherwise a
-- member cannot block a stranger whose reel they were just shown.
drop policy if exists "Users manage own blocks" on public.user_blocks;
create policy "Users manage own blocks" on public.user_blocks
  for all to authenticated
  using (blocker_id = (select auth.uid())::text)
  with check (
    blocker_id = (select auth.uid())::text
    and (
      church_id = public.get_church_id()
      or church_id = public.grace_connect_global_scope_id()
    )
  );

-- can_view_reel already matches user_blocks on the pair of user ids without
-- reference to church_id, so a global block hides that creator's reels
-- immediately. No change needed there -- recorded here because it is the
-- reason this scope change is safe.
