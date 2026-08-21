-- Quote/scripture share backgrounds move from bundled Flutter assets to
-- Supabase Storage: adding a new background (or fixing one) used to
-- require a full app release; now it's an upload. A public bucket is
-- correct here -- these are decorative marketing-style images with no
-- user data in them, the same trust level as the app icon or notification
-- icon already served directly from the app bundle.
insert into storage.buckets (id, name, public)
values ('quote-backgrounds', 'quote-backgrounds', true)
on conflict (id) do update set public = true;

-- Public buckets already let anyone GET an object without a policy match,
-- but an explicit SELECT policy is added anyway so this bucket's read
-- access is visible and auditable in the dashboard rather than relying
-- solely on the bucket-level public flag.
drop policy if exists "quote backgrounds are public to read" on storage.objects;
create policy "quote backgrounds are public to read"
  on storage.objects for select
  using (bucket_id = 'quote-backgrounds');
