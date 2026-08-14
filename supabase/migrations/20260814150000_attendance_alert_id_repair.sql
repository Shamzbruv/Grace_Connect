-- Repair attendance-care alerts on databases where priority_follow_ups
-- predates the canonical UUID default. `create table if not exists` does not
-- retrofit defaults onto an existing column, so refreshes could attempt an
-- insert with NULL id and fail with SQLSTATE 23502.

create extension if not exists pgcrypto;

update public.priority_follow_ups
set id = gen_random_uuid()
where id is null;

alter table public.priority_follow_ups
  alter column id set default gen_random_uuid(),
  alter column id set not null;

comment on column public.priority_follow_ups.id is
  'Server-generated UUID for idempotent attendance care alerts.';
