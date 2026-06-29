-- Ensure feed and status uploads use the bucket the Flutter app writes to.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community_media',
  'community_media',
  true,
  52428800,
  array[
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
    'video/mp4',
    'video/quicktime',
    'video/x-m4v',
    'video/webm'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users read community media"
  on storage.objects;
create policy "Authenticated users read community media"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'community_media');

drop policy if exists "Authenticated users upload community media"
  on storage.objects;
create policy "Authenticated users upload community media"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'community_media');

drop policy if exists "Authenticated users remove community media"
  on storage.objects;
create policy "Authenticated users remove community media"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'community_media');
