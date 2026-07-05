-- Track active in-app livestream viewers with short-lived heartbeats.
create table if not exists public.live_stream_viewers (
  church_id text not null,
  user_id text not null,
  last_seen_at timestamptz not null default now(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (church_id, user_id)
);

create index if not exists live_stream_viewers_church_active_idx
  on public.live_stream_viewers (church_id, is_active, last_seen_at desc);

alter table public.live_stream_viewers enable row level security;

drop trigger if exists trg_live_stream_viewers_updated_at
  on public.live_stream_viewers;
create trigger trg_live_stream_viewers_updated_at
  before update on public.live_stream_viewers
  for each row execute function public.set_updated_at();

drop policy if exists "Live viewers read same church presence"
  on public.live_stream_viewers;
create policy "Live viewers read same church presence"
  on public.live_stream_viewers
  for select
  using (
    exists (
      select 1
      from public.users u
      where (u.id = auth.uid() or u.uid = auth.uid()::text)
        and u."placeId" = live_stream_viewers.church_id
    )
  );

drop policy if exists "Live viewers insert own presence"
  on public.live_stream_viewers;
create policy "Live viewers insert own presence"
  on public.live_stream_viewers
  for insert
  with check (
    user_id = auth.uid()::text
    and exists (
      select 1
      from public.users u
      where (u.id = auth.uid() or u.uid = auth.uid()::text)
        and u."placeId" = live_stream_viewers.church_id
    )
  );

drop policy if exists "Live viewers update own presence"
  on public.live_stream_viewers;
create policy "Live viewers update own presence"
  on public.live_stream_viewers
  for update
  using (user_id = auth.uid()::text)
  with check (
    user_id = auth.uid()::text
    and exists (
      select 1
      from public.users u
      where (u.id = auth.uid() or u.uid = auth.uid()::text)
        and u."placeId" = live_stream_viewers.church_id
    )
  );

grant select, insert, update on public.live_stream_viewers to authenticated;
