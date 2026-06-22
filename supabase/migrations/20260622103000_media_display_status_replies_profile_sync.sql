alter table public.community_posts
  add column if not exists media_fit text not null default 'cover',
  add column if not exists media_aspect_ratio double precision;

alter table public.community_stories
  add column if not exists media_fit text not null default 'cover',
  add column if not exists media_aspect_ratio double precision;

alter table public.direct_messages
  add column if not exists reply_context jsonb not null default '{}'::jsonb;

create index if not exists direct_messages_reply_context_idx
  on public.direct_messages using gin (reply_context);

update public.community_posts
  set media_fit = 'cover'
  where media_fit is null or media_fit = '';

update public.community_stories
  set media_fit = 'cover'
  where media_fit is null or media_fit = '';

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
    where author_id = auth.uid()::text;

  update public.community_stories
    set author_photo = photo_url
    where author_id = auth.uid()::text;

  update public.community_comments
    set author_photo = photo_url
    where author_id = auth.uid()::text;
end;
$$;

grant execute on function public.sync_user_profile_photo_references(text)
  to authenticated;
