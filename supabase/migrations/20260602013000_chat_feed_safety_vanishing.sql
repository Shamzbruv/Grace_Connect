-- Chat/media safety, 30-day vanishing cleanup, reports, and blocks.

create extension if not exists pgcrypto;

alter table public.direct_conversations
  add column if not exists hidden_for text[] not null default '{}'::text[];

alter table public.direct_messages
  add column if not exists media_url text,
  add column if not exists media_path text,
  add column if not exists media_type text not null default 'text',
  add column if not exists duration_seconds integer,
  add column if not exists delivered_at timestamptz,
  add column if not exists read_at timestamptz,
  add column if not exists deleted_for text[] not null default '{}'::text[],
  add column if not exists expires_at timestamptz not null default (now() + interval '30 days');

alter table public.direct_messages
  alter column text set default '';

update public.direct_messages
  set media_type = coalesce(nullif(media_type, ''), 'text'),
      delivered_at = case
        when is_read and delivered_at is null then created_at
        else delivered_at
      end,
      read_at = case
        when is_read and read_at is null then created_at
        else read_at
      end
  where media_type is null
     or media_type = ''
     or (is_read and (delivered_at is null or read_at is null));

create index if not exists direct_messages_expiry_idx
  on public.direct_messages (expires_at);

create index if not exists direct_messages_unread_idx
  on public.direct_messages (conversation_id, sender_id, is_read, created_at desc);

alter table public.community_posts
  add column if not exists media_path text,
  add column if not exists expires_at timestamptz not null default (now() + interval '30 days');

update public.community_posts
  set media_path = nullif(split_part(media_url, '/community_media/', 2), '')
  where media_path is null
    and media_url is not null
    and position('/community_media/' in media_url) > 0;

create index if not exists community_posts_expiry_idx
  on public.community_posts (expires_at);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat_media',
  'chat_media',
  true,
  52428800,
  array[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'audio/aac',
    'audio/m4a',
    'audio/mpeg',
    'audio/mp4',
    'audio/wav',
    'audio/webm'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Authenticated users read chat media" on storage.objects;
create policy "Authenticated users read chat media"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'chat_media');

drop policy if exists "Authenticated users upload chat media" on storage.objects;
create policy "Authenticated users upload chat media"
  on storage.objects
  for insert
  to authenticated
  with check (bucket_id = 'chat_media');

drop policy if exists "Authenticated users remove own chat media" on storage.objects;
create policy "Authenticated users remove own chat media"
  on storage.objects
  for delete
  to authenticated
  using (bucket_id = 'chat_media');

create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  blocker_id text not null,
  blocked_user_id text not null,
  reason text,
  created_at timestamptz not null default now(),
  constraint user_blocks_no_self check (blocker_id <> blocked_user_id),
  constraint user_blocks_unique unique (blocker_id, blocked_user_id)
);

create index if not exists user_blocks_blocker_idx
  on public.user_blocks (blocker_id, created_at desc);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_user_id);

alter table public.user_blocks enable row level security;

drop policy if exists "Users manage own blocks" on public.user_blocks;
create policy "Users manage own blocks"
  on public.user_blocks
  for all
  to authenticated
  using (blocker_id = auth.uid()::text)
  with check (
    blocker_id = auth.uid()::text
    and church_id = public.get_church_id()
  );

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  reporter_id text not null,
  reported_user_id text,
  content_type text not null,
  content_id text,
  reason text not null,
  description text,
  status text not null default 'pending',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text,
  constraint content_reports_status_check
    check (status in ('pending', 'reviewed', 'dismissed', 'action_taken'))
);

create index if not exists content_reports_church_status_idx
  on public.content_reports (church_id, status, created_at desc);

create index if not exists content_reports_reporter_idx
  on public.content_reports (reporter_id, created_at desc);

alter table public.content_reports enable row level security;

drop policy if exists "Users create reports" on public.content_reports;
create policy "Users create reports"
  on public.content_reports
  for insert
  to authenticated
  with check (
    reporter_id = auth.uid()::text
    and church_id = public.get_church_id()
  );

drop policy if exists "Users view own reports" on public.content_reports;
create policy "Users view own reports"
  on public.content_reports
  for select
  to authenticated
  using (
    reporter_id = auth.uid()::text
    or (
      church_id = public.get_church_id()
      and public.has_any_role(array['Pastor', 'Senior Pastor', 'Secretary'])
    )
  );

drop policy if exists "Leaders update reports" on public.content_reports;
create policy "Leaders update reports"
  on public.content_reports
  for update
  to authenticated
  using (
    church_id = public.get_church_id()
    and public.has_any_role(array['Pastor', 'Senior Pastor', 'Secretary'])
  )
  with check (
    church_id = public.get_church_id()
    and public.has_any_role(array['Pastor', 'Senior Pastor', 'Secretary'])
  );

create or replace function public.delete_direct_message_media()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if old.media_path is not null and old.media_path <> '' then
    delete from storage.objects
      where bucket_id = 'chat_media'
        and name = old.media_path;
  end if;

  return old;
end;
$$;

drop trigger if exists direct_message_media_cleanup
  on public.direct_messages;
create trigger direct_message_media_cleanup
  after delete on public.direct_messages
  for each row
  execute function public.delete_direct_message_media();

create or replace function public.delete_community_post_media()
returns trigger
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  path text;
begin
  path := coalesce(
    nullif(old.media_path, ''),
    nullif(split_part(old.media_url, '/community_media/', 2), '')
  );

  if path is not null and path <> '' then
    delete from storage.objects
      where bucket_id = 'community_media'
        and name = path;
  end if;

  return old;
end;
$$;

drop trigger if exists community_post_media_cleanup
  on public.community_posts;
create trigger community_post_media_cleanup
  after delete on public.community_posts
  for each row
  execute function public.delete_community_post_media();

create or replace function public.cleanup_vanishing_content()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_posts integer := 0;
  deleted_messages integer := 0;
begin
  delete from public.community_comments
    where post_id in (
      select id
      from public.community_posts
      where coalesce(expires_at, created_at + interval '30 days') <= now()
    );

  delete from public.community_posts
    where coalesce(expires_at, created_at + interval '30 days') <= now();
  get diagnostics deleted_posts = row_count;

  delete from public.direct_messages
    where coalesce(expires_at, created_at + interval '30 days') <= now();
  get diagnostics deleted_messages = row_count;

  return jsonb_build_object(
    'deleted_posts', deleted_posts,
    'deleted_messages', deleted_messages
  );
end;
$$;

grant execute on function public.cleanup_vanishing_content()
  to authenticated;

drop policy if exists "Members create direct conversations"
  on public.direct_conversations;
create policy "Members create direct conversations"
  on public.direct_conversations
  for insert
  to authenticated
  with check (
    created_by = auth.uid()::text
    and auth.uid()::text = any(member_ids)
    and church_id = public.get_church_id()
    and (
      select count(*)
      from public.users u
      where u.uid = any(member_ids)
        and u."placeId" = church_id
        and coalesce(u."allowMessages", true)
    ) = 2
    and not exists (
      select 1
      from public.user_blocks b
      where (b.blocker_id = member_ids[1] and b.blocked_user_id = member_ids[2])
         or (b.blocker_id = member_ids[2] and b.blocked_user_id = member_ids[1])
    )
  );

drop policy if exists "Members send own direct messages"
  on public.direct_messages;
create policy "Members send own direct messages"
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()::text
    and (
      nullif(trim(coalesce(text, '')), '') is not null
      or nullif(trim(coalesce(media_url, '')), '') is not null
    )
    and exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and auth.uid()::text = any(c.member_ids)
        and not exists (
          select 1
          from public.user_blocks b
          where (
              b.blocker_id = auth.uid()::text
              and b.blocked_user_id = any(c.member_ids)
              and b.blocked_user_id <> auth.uid()::text
            )
             or (
              b.blocked_user_id = auth.uid()::text
              and b.blocker_id = any(c.member_ids)
              and b.blocker_id <> auth.uid()::text
            )
        )
    )
  );

drop policy if exists "Members delete own direct messages"
  on public.direct_messages;
create policy "Members delete own direct messages"
  on public.direct_messages
  for delete
  to authenticated
  using (sender_id = auth.uid()::text);

alter table public.user_blocks replica identity full;
alter table public.content_reports replica identity full;
