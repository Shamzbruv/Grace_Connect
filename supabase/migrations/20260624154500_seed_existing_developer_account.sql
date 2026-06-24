-- Sync the existing app-level developer owner into the dedicated portal table.
-- The Flutter app already used users."isDeveloper"; the portal uses developer_accounts.

insert into public.developer_accounts (user_id, email, developer_role, status)
select
  u.id,
  lower(coalesce(nullif(u.email, ''), au.email)),
  'super_developer',
  'active'
from public.users u
left join auth.users au on au.id = u.id
where coalesce(u."isDeveloper", false) = true
  and coalesce(nullif(u.email, ''), au.email) is not null
on conflict (email) do update
  set user_id = coalesce(excluded.user_id, public.developer_accounts.user_id),
      developer_role = 'super_developer',
      status = 'active';
