-- Harden beta care requests, testimony notifications, and community media.

create extension if not exists pgcrypto;

do $$
declare
  id_type text;
begin
  select data_type
    into id_type
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'counseling_requests'
      and column_name = 'id';

  if id_type = 'uuid' then
    execute 'alter table public.counseling_requests alter column id set default gen_random_uuid()';
  elsif id_type is not null then
    execute 'alter table public.counseling_requests alter column id set default gen_random_uuid()::text';
  end if;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'community_media',
  'community_media',
  true,
  209715200,
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

create or replace function public.notify_church_on_testimony()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient record;
  actor_uuid uuid;
  author_label text;
begin
  begin
    actor_uuid := new.author_id::uuid;
  exception when others then
    actor_uuid := null;
  end;

  author_label := case
    when coalesce(new.is_anonymous, false) then 'A church member'
    else coalesce(nullif(trim(new.author_name), ''), 'A church member')
  end;

  for recipient in
    select distinct u.uid::uuid as user_id
    from public.users u
    where u."placeId" = new.church_id
      and nullif(trim(u.uid), '') is not null
      and u.uid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and u.uid <> coalesce(new.author_id, '')
      and coalesce(u."accountState", 'active') = 'active'
  loop
    perform public.create_notification(
      recipient.user_id,
      actor_uuid,
      'testimony',
      'New testimony',
      author_label || ' shared a testimony.',
      new.church_id,
      'testimonies',
      new.id::text,
      '/testimonies'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_church_on_testimony on public.testimonies;
create trigger trg_notify_church_on_testimony
  after insert on public.testimonies
  for each row execute function public.notify_church_on_testimony();
