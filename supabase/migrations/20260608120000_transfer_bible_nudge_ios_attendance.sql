-- Church transfer workflow, Bible Nudge, and notification plumbing.

create extension if not exists pgcrypto;

create or replace function public.is_pastoral_leader_for_church(
  target_church_id text
)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from public.users u
    cross join lateral unnest(coalesce(u.roles, '{}'::text[])) role_name
    where u.id = auth.uid()
      and u."placeId" = target_church_id
      and lower(regexp_replace(role_name, '[^a-zA-Z0-9]+', '_', 'g')) in (
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor'
      )
  );
$$;

create table if not exists public.church_transfer_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_name text not null default 'Member',
  user_email text not null default '',
  current_church_id text not null,
  current_church_name text not null default '',
  target_church_id text not null,
  target_church_name text not null default '',
  reason text not null default '',
  contact_phone text not null default '',
  status text not null default 'submitted'
    check (
      status in (
        'submitted',
        'pastor_review',
        'sent_to_target_pastor',
        'approved',
        'declined',
        'completed',
        'cancelled'
      )
    ),
  pastor_notes text not null default '',
  target_pastor_notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists church_transfer_user_idx
  on public.church_transfer_requests (user_id, created_at desc);

create index if not exists church_transfer_current_church_idx
  on public.church_transfer_requests (current_church_id, status, created_at desc);

create index if not exists church_transfer_target_church_idx
  on public.church_transfer_requests (target_church_id, status, created_at desc);

alter table public.church_transfer_requests enable row level security;

drop policy if exists "Members create own transfer requests" on public.church_transfer_requests;
create policy "Members create own transfer requests"
  on public.church_transfer_requests
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and current_church_id = public.get_church_id()
  );

drop policy if exists "Transfer request visibility" on public.church_transfer_requests;
create policy "Transfer request visibility"
  on public.church_transfer_requests
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_pastoral_leader_for_church(current_church_id)
    or public.is_pastoral_leader_for_church(target_church_id)
  );

drop policy if exists "Transfer request updates" on public.church_transfer_requests;
create policy "Transfer request updates"
  on public.church_transfer_requests
  for update
  to authenticated
  using (
    user_id = auth.uid()
    or public.is_pastoral_leader_for_church(current_church_id)
    or public.is_pastoral_leader_for_church(target_church_id)
  )
  with check (
    user_id = auth.uid()
    or public.is_pastoral_leader_for_church(current_church_id)
    or public.is_pastoral_leader_for_church(target_church_id)
  );

create or replace function public.set_church_transfer_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_set_church_transfer_updated_at
  on public.church_transfer_requests;
create trigger trg_set_church_transfer_updated_at
  before update on public.church_transfer_requests
  for each row execute function public.set_church_transfer_updated_at();

create or replace function public.notify_church_transfer_insert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  pastor_record record;
begin
  for pastor_record in
    select distinct u.id
    from public.users u
    cross join lateral unnest(coalesce(u.roles, '{}'::text[])) role_name
    where u."placeId" = new.current_church_id
      and lower(regexp_replace(role_name, '[^a-zA-Z0-9]+', '_', 'g')) in (
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor'
      )
  loop
    perform public.create_notification(
      pastor_record.id,
      new.user_id,
      'church_transfer_request',
      'Church transfer request',
      new.user_name || ' requested a transfer to ' || new.target_church_name || '.',
      new.current_church_id,
      'church_transfer_requests',
      new.id::text,
      '/church_transfer'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_church_transfer_insert
  on public.church_transfer_requests;
create trigger trg_notify_church_transfer_insert
  after insert on public.church_transfer_requests
  for each row execute function public.notify_church_transfer_insert();

create or replace function public.notify_church_transfer_update()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  pastor_record record;
begin
  if new.status is distinct from old.status then
    perform public.create_notification(
      new.user_id,
      auth.uid(),
      'church_transfer_update',
      'Transfer request updated',
      'Your transfer request is now: ' || replace(new.status, '_', ' ') || '.',
      new.current_church_id,
      'church_transfer_requests',
      new.id::text,
      '/church_transfer'
    );

    if new.status = 'sent_to_target_pastor' then
      for pastor_record in
        select distinct u.id
        from public.users u
        cross join lateral unnest(coalesce(u.roles, '{}'::text[])) role_name
        where u."placeId" = new.target_church_id
          and lower(regexp_replace(role_name, '[^a-zA-Z0-9]+', '_', 'g')) in (
            'pastor',
            'senior_pastor',
            'assistant_pastor',
            'acting_pastor'
          )
      loop
        perform public.create_notification(
          pastor_record.id,
          auth.uid(),
          'church_transfer_incoming',
          'Incoming transfer request',
          new.user_name || ' may transfer from ' || new.current_church_name || '.',
          new.target_church_id,
          'church_transfer_requests',
          new.id::text,
          '/church_transfer'
        );
      end loop;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_church_transfer_update
  on public.church_transfer_requests;
create trigger trg_notify_church_transfer_update
  after update on public.church_transfer_requests
  for each row execute function public.notify_church_transfer_update();

create table if not exists public.bible_nudges (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_name text not null default 'Someone',
  recipient_id uuid not null references auth.users(id) on delete cascade,
  recipient_name text not null default 'Member',
  church_id text not null,
  message text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint bible_nudges_no_self check (sender_id <> recipient_id)
);

create index if not exists bible_nudges_sender_idx
  on public.bible_nudges (sender_id, created_at desc);

create index if not exists bible_nudges_recipient_idx
  on public.bible_nudges (recipient_id, status, created_at desc);

alter table public.bible_nudges enable row level security;

drop policy if exists "Members create Bible Nudges" on public.bible_nudges;
create policy "Members create Bible Nudges"
  on public.bible_nudges
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and church_id = public.get_church_id()
  );

drop policy if exists "Participants view Bible Nudges" on public.bible_nudges;
create policy "Participants view Bible Nudges"
  on public.bible_nudges
  for select
  to authenticated
  using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
  );

drop policy if exists "Recipients respond to Bible Nudges" on public.bible_nudges;
create policy "Recipients respond to Bible Nudges"
  on public.bible_nudges
  for update
  to authenticated
  using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
  )
  with check (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
  );

alter table public.church_transfer_requests replica identity full;
alter table public.bible_nudges replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'church_transfer_requests'
    ) then
      execute 'alter publication supabase_realtime add table public.church_transfer_requests';
    end if;

    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'bible_nudges'
    ) then
      execute 'alter publication supabase_realtime add table public.bible_nudges';
    end if;
  end if;
end;
$$;
