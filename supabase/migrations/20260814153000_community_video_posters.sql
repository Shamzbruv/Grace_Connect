-- Persist a lightweight poster beside each uploaded video. The Flutter feed
-- renders this image immediately while Android prepares the video texture.
alter table public.community_posts
  add column if not exists media_thumbnail_url text,
  add column if not exists media_thumbnail_path text;

alter table public.community_stories
  add column if not exists media_thumbnail_url text,
  add column if not exists media_thumbnail_path text;

-- Older clients defaulted unknown media dimensions to cover, which is what
-- clipped wide flyers in a portrait status. Preserve the complete asset for
-- those legacy rows; new clients persist an explicit measured ratio and the
-- member's chosen format.
update public.community_posts
set media_fit = 'contain'
where media_url is not null
  and media_aspect_ratio is null
  and media_fit = 'cover';

update public.community_stories
set media_fit = 'contain'
where media_url is not null
  and media_aspect_ratio is null
  and media_fit = 'cover';

comment on column public.community_posts.media_thumbnail_url is
  'Public immutable poster image displayed before a community video is ready.';
comment on column public.community_posts.media_thumbnail_path is
  'Storage object path used to remove a post video poster through the Storage API.';
comment on column public.community_stories.media_thumbnail_url is
  'Public immutable poster image displayed before a status video is ready.';
comment on column public.community_stories.media_thumbnail_path is
  'Storage object path used to remove a status video poster through the Storage API.';

notify pgrst, 'reload schema';
