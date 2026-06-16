-- Adds a contact audience so users can hide email/phone or limit it to their church.
alter table public.users
  add column if not exists "contactInfoVisibility" text not null default 'church';

alter table public.users
  drop constraint if exists users_contact_info_visibility_check;

alter table public.users
  add constraint users_contact_info_visibility_check
  check ("contactInfoVisibility" in ('everyone', 'church', 'private'));

update public.users
set "contactInfoVisibility" = 'private'
where coalesce("showContactInfo", true) = false;
