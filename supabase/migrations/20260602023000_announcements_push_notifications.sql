-- Dedicated church announcements with notification fanout.

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  church_id text not null,
  author_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null default 'Grace Connect',
  title text not null,
  body text not null,
  priority text not null default 'normal'
    check (priority in ('normal', 'important', 'urgent')),
  expires_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists announcements_church_created_idx
  on public.announcements (church_id, created_at desc)
  where deleted_at is null;

create index if not exists announcements_author_idx
  on public.announcements (author_id, created_at desc);

alter table public.announcements enable row level security;

drop policy if exists "Church members view announcements" on public.announcements;
create policy "Church members view announcements"
  on public.announcements
  for select
  to authenticated
  using (
    church_id = public.get_church_id()
    and deleted_at is null
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "Announcement publishers insert announcements" on public.announcements;
create policy "Announcement publishers insert announcements"
  on public.announcements
  for insert
  to authenticated
  with check (
    church_id = public.get_church_id()
    and author_id = auth.uid()
    and public.has_any_role(array[
      'Pastor',
      'Senior Pastor',
      'Assistant Pastor',
      'Acting Pastor',
      'Church Admin',
      'Admin',
      'Administrator',
      'Secretary',
      'Church Secretary'
    ])
  );

drop policy if exists "Announcement publishers update announcements" on public.announcements;
create policy "Announcement publishers update announcements"
  on public.announcements
  for update
  to authenticated
  using (
    church_id = public.get_church_id()
    and deleted_at is null
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
    )
  )
  with check (
    church_id = public.get_church_id()
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
    )
  );

drop policy if exists "Announcement publishers delete announcements" on public.announcements;
create policy "Announcement publishers delete announcements"
  on public.announcements
  for delete
  to authenticated
  using (
    church_id = public.get_church_id()
    and (
      author_id = auth.uid()
      or public.has_any_role(array[
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Admin',
        'Administrator',
        'Secretary',
        'Church Secretary'
      ])
    )
  );

grant select, insert, update, delete on public.announcements to authenticated;

create or replace function public.set_announcement_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_set_announcement_updated_at on public.announcements;
create trigger trg_set_announcement_updated_at
  before update on public.announcements
  for each row execute function public.set_announcement_updated_at();

create or replace function public.notify_on_announcement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  member_record record;
  notification_body text;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  notification_body := left(
    regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g'),
    220
  );

  for member_record in
    select id
    from public.users
    where "placeId" = new.church_id
      and id is not null
  loop
    perform public.create_notification(
      member_record.id,
      new.author_id,
      'announcement',
      coalesce(nullif(new.title, ''), 'New church announcement'),
      notification_body,
      new.church_id,
      'announcements',
      new.id::text,
      '/announcements'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_on_announcement on public.announcements;
create trigger trg_notify_on_announcement
  after insert on public.announcements
  for each row execute function public.notify_on_announcement();

alter table public.announcements replica identity full;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'announcements'
  ) then
    execute 'alter publication supabase_realtime add table public.announcements';
  end if;
exception when undefined_object then
  null;
end;
$$;
