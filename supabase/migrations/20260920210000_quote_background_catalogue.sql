-- Developer-managed catalogue for share-card backgrounds.
--
-- The catalogue lived in catalogue_manifest.json inside the storage bucket.
-- Editing that from the app means download, mutate, re-upload: two developers
-- adding a background at once would have one silently overwrite the other,
-- and a failed upload halfway through leaves the catalogue corrupt for every
-- member. A table gives per-row writes, real constraints, and an immediate
-- read for everyone.
--
-- The images themselves stay in the public bucket. The table describes them.

create table if not exists public.quote_backgrounds (
  id uuid primary key default gen_random_uuid(),
  file_name text not null unique,
  title text not null,
  category text not null default '',
  recommended_text_color text not null default 'white',
  safe_text_area text not null default 'center',
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quote_backgrounds_safe_area_check check (
    safe_text_area in ('center', 'upper-center', 'left-center', 'center-right')
  ),
  constraint quote_backgrounds_title_length_check check (
    char_length(title) between 1 and 120
  ),
  constraint quote_backgrounds_file_name_check check (
    -- Kept to a plain file name: the app joins this onto a fixed bucket
    -- prefix, so a value containing a slash or '..' would point the share
    -- card at some other object entirely.
    file_name ~ '^[A-Za-z0-9._-]+\.(png|jpg|jpeg|webp)$'
  )
);

create index if not exists quote_backgrounds_active_idx
  on public.quote_backgrounds (is_active, sort_order, created_at);

alter table public.quote_backgrounds enable row level security;

-- Everyone reads the active ones: the share customiser is open to every
-- member, and these images carry no user data.
drop policy if exists "quote backgrounds are readable" on public.quote_backgrounds;
create policy "quote backgrounds are readable"
  on public.quote_backgrounds for select
  to anon, authenticated
  using (is_active);

-- Only developers change the catalogue.
drop policy if exists "developers manage quote backgrounds" on public.quote_backgrounds;
create policy "developers manage quote backgrounds"
  on public.quote_backgrounds for all
  to authenticated
  using (public.current_developer_role() is not null)
  with check (public.current_developer_role() is not null);

-- A developer viewing the admin screen has to see inactive rows too, which
-- the read policy above deliberately hides from members. The ALL policy
-- covers that for developers.

-- Storage: the bucket was read-only to everyone. Uploading a new background
-- from the developer screen needs write access, scoped to developers and to
-- this bucket alone.
drop policy if exists "developers write quote backgrounds" on storage.objects;
create policy "developers write quote backgrounds"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'quote-backgrounds'
    and public.current_developer_role() is not null
  );

drop policy if exists "developers update quote backgrounds" on storage.objects;
create policy "developers update quote backgrounds"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'quote-backgrounds'
    and public.current_developer_role() is not null
  );

drop policy if exists "developers delete quote backgrounds" on storage.objects;
create policy "developers delete quote backgrounds"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'quote-backgrounds'
    and public.current_developer_role() is not null
  );

-- Seed from the manifest that is live today, so the catalogue the app shows
-- does not change the moment this deploys.
insert into public.quote_backgrounds
  (file_name, title, category, recommended_text_color, safe_text_area, sort_order)
values
  ('01_midnight_grace.png', 'Midnight Grace', 'Dark / Prayer', 'white', 'center', 1),
  ('02_morning_mercy.png', 'Morning Mercy', 'Light / Hope', '#10141C', 'upper-center', 2),
  ('03_living_water.png', 'Living Water', 'Nature / Peace', 'white', 'upper-center', 3),
  ('04_quiet_prayer.png', 'Quiet Prayer', 'Dark / Prayer', 'white', 'center', 4),
  ('05_faith_lines.png', 'Faith Lines', 'Abstract / Faith', 'white', 'center', 5),
  ('06_open_heavens.png', 'Open Heavens', 'Sky / Worship', 'white', 'upper-center', 6),
  ('07_cross_glow.png', 'Cross Glow', 'Cross / Devotion', 'white', 'center', 7),
  ('08_cathedral_glass.png', 'Cathedral Glass', 'Sanctuary / Reverence', 'white', 'center', 8),
  ('09_grace_garden.png', 'Grace Garden', 'Nature / Growth', 'white', 'upper-center', 9),
  ('10_connected_in_grace.png', 'Connected in Grace', 'Community / Connection', 'white', 'center', 10)
on conflict (file_name) do nothing;

-- Listing for the developer screen: returns inactive rows too, which the
-- member-facing read policy hides.
create or replace function public.developer_list_quote_backgrounds()
returns setof public.quote_backgrounds
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform public.require_developer();
  return query
    select * from public.quote_backgrounds
    order by sort_order, created_at;
end;
$$;

revoke all on function public.developer_list_quote_backgrounds() from public, anon;
grant execute on function public.developer_list_quote_backgrounds() to authenticated;
