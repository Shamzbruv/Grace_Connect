create extension if not exists pgcrypto;

create table if not exists public.live_stream_viewers (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  user_id text not null,
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (church_id, user_id)
);

create index if not exists live_stream_viewers_active_idx
  on public.live_stream_viewers (church_id, is_active, last_seen_at desc);

alter table public.live_stream_viewers enable row level security;

create or replace function public.is_live_stream_church_member(p_church_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.uid = auth.uid()::text
      and u."placeId" = p_church_id
  );
$$;

drop policy if exists "Members manage their own live stream heartbeat"
  on public.live_stream_viewers;
create policy "Members manage their own live stream heartbeat"
  on public.live_stream_viewers
  for all
  to authenticated
  using (user_id = auth.uid()::text)
  with check (
    user_id = auth.uid()::text
    and public.is_live_stream_church_member(church_id)
  );

create or replace function public.record_live_stream_viewer_heartbeat(
  p_church_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id text := trim(coalesce(p_church_id, ''));
  v_user_id text := auth.uid()::text;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if v_church_id = '' or not public.is_live_stream_church_member(v_church_id) then
    raise exception 'Church membership required.';
  end if;

  insert into public.live_stream_viewers (
    church_id,
    user_id,
    last_seen_at,
    is_active,
    updated_at
  )
  values (
    v_church_id,
    v_user_id,
    now(),
    true,
    now()
  )
  on conflict (church_id, user_id)
  do update set
    last_seen_at = excluded.last_seen_at,
    is_active = true,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function public.clear_live_stream_viewer_heartbeat(
  p_church_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_church_id text := trim(coalesce(p_church_id, ''));
  v_user_id text := auth.uid()::text;
begin
  if v_user_id is null or v_church_id = '' then
    return;
  end if;

  update public.live_stream_viewers
  set is_active = false,
      updated_at = now()
  where church_id = v_church_id
    and user_id = v_user_id;
end;
$$;

create or replace function public.get_live_stream_viewer_count(
  p_church_id text
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_church_id text := trim(coalesce(p_church_id, ''));
  v_count integer := 0;
begin
  if auth.uid() is null then
    return 0;
  end if;

  if v_church_id = '' or not public.is_live_stream_church_member(v_church_id) then
    return 0;
  end if;

  select count(*)::integer
  into v_count
  from public.live_stream_viewers
  where church_id = v_church_id
    and is_active = true
    and last_seen_at >= now() - interval '90 seconds';

  return coalesce(v_count, 0);
end;
$$;

grant execute on function public.record_live_stream_viewer_heartbeat(text)
  to authenticated;
grant execute on function public.clear_live_stream_viewer_heartbeat(text)
  to authenticated;
grant execute on function public.get_live_stream_viewer_count(text)
  to authenticated;
