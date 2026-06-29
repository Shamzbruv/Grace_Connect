-- The remote project already had a support_tickets table before the canonical
-- issue-report migration. Normalize that existing table without assuming its
-- original id type.

alter table public.support_tickets
  add column if not exists "ticketId" text,
  add column if not exists "userId" text,
  add column if not exists uid text,
  add column if not exists "reporterEmail" text,
  add column if not exists "churchId" text,
  add column if not exists roles text[] default '{}'::text[],
  add column if not exists "issueType" text default 'Bug / Something isn''t working',
  add column if not exists "appSection" text default 'Other',
  add column if not exists title text,
  add column if not exists subject text,
  add column if not exists summary text,
  add column if not exists description text,
  add column if not exists impact text default 'Medium',
  add column if not exists priority text default 'medium',
  add column if not exists "deviceInfo" jsonb default '{}'::jsonb,
  add column if not exists "attachmentUrls" text[] default '{}'::text[],
  add column if not exists status text default 'open',
  add column if not exists developer_notes text,
  add column if not exists acknowledged_by uuid,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists resolved_by uuid,
  add column if not exists resolved_at timestamptz,
  add column if not exists "createdAt" timestamptz default now(),
  add column if not exists updated_at timestamptz default now();

do $$
declare
  id_data_type text;
  constraint_name text;
begin
  select data_type
    into id_data_type
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'support_tickets'
    and column_name = 'id';

  if id_data_type = 'uuid' then
    alter table public.support_tickets
      alter column id set default gen_random_uuid();
  elsif id_data_type = 'text' then
    alter table public.support_tickets
      alter column id set default replace(gen_random_uuid()::text, '-', '');
  end if;

  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'support_tickets'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.support_tickets drop constraint if exists %I', constraint_name);
  end loop;
end $$;

update public.support_tickets
set "ticketId" = coalesce(nullif("ticketId", ''), id::text, replace(gen_random_uuid()::text, '-', '')),
    uid = coalesce(nullif(uid, ''), nullif("userId", '')),
    "userId" = coalesce(nullif("userId", ''), nullif(uid, '')),
    title = coalesce(nullif(title, ''), nullif(summary, ''), nullif(subject, '')),
    subject = coalesce(nullif(subject, ''), nullif(summary, ''), nullif(title, '')),
    summary = coalesce(nullif(summary, ''), nullif(title, ''), nullif(subject, ''), 'Issue report'),
    description = coalesce(nullif(description, ''), nullif(summary, ''), 'No description provided.'),
    impact = coalesce(nullif(impact, ''), 'Medium'),
    priority = coalesce(nullif(priority, ''), lower(coalesce(nullif(impact, ''), 'medium'))),
    status = case
      when status = 'in_progress' then 'in_review'
      when status in ('open', 'acknowledged', 'in_review', 'resolved', 'closed') then status
      else 'open'
    end,
    "createdAt" = coalesce("createdAt", now()),
    updated_at = coalesce(updated_at, now());

alter table public.support_tickets
  alter column "ticketId" set default replace(gen_random_uuid()::text, '-', ''),
  alter column roles set default '{}'::text[],
  alter column "issueType" set default 'Bug / Something isn''t working',
  alter column "appSection" set default 'Other',
  alter column impact set default 'Medium',
  alter column priority set default 'medium',
  alter column "deviceInfo" set default '{}'::jsonb,
  alter column "attachmentUrls" set default '{}'::text[],
  alter column status set default 'open',
  alter column "createdAt" set default now(),
  alter column updated_at set default now();

create unique index if not exists support_tickets_ticket_id_unique_idx
  on public.support_tickets ("ticketId");

alter table public.support_tickets
  add constraint support_tickets_status_check
  check (status in ('open', 'acknowledged', 'in_review', 'resolved', 'closed'));

create index if not exists support_tickets_status_idx
  on public.support_tickets (status, "createdAt" desc);

create index if not exists support_tickets_church_idx
  on public.support_tickets ("churchId", status);
