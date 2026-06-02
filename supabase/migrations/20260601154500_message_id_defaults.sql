create extension if not exists pgcrypto;

alter table if exists public.direct_messages
  alter column id set default gen_random_uuid();

alter table if exists public.group_messages
  alter column id set default gen_random_uuid();
