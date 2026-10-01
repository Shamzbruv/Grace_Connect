-- Include explicit deletes in maintenance protection. Auth's internal account
-- cascades remain permitted by the existing guard; Storage API deletion is separate.
do $$ declare t record; begin
  for t in select table_name from private.platform_reset_tables where table_name<>'developer_accounts' loop
    execute format('drop trigger platform_reset_write_guard on public.%I',t.table_name);
    execute format('create trigger platform_reset_write_guard before insert or update or delete on public.%I for each statement execute function private.guard_platform_reset_writes()',t.table_name);
  end loop;
end $$;

-- The portal updates last_login_at to authenticate its session. Allow just that
-- heartbeat during cleanup, rather than exempting all developer-account writes.
create or replace function private.guard_developer_reset_changes()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if current_setting('role')='authenticated' and not exists(select 1 from auth.users where id=auth.uid()) then
    raise exception 'Your account is no longer active. Sign in again.' using errcode='42501';
  end if;
  if exists(select 1 from private.platform_reset_control where phase not in ('idle','complete'))
    and not(coalesce(current_setting('grace.reset_worker',true),'')='on'
      and current_setting('role') in ('service_role','postgres','none')) then
    if tg_op<>'UPDATE' or (to_jsonb(new)-'last_login_at') is distinct from (to_jsonb(old)-'last_login_at') then
      raise exception 'Grace Connect is being reset. Please try again shortly.' using errcode='55000';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.guard_developer_reset_changes() from public,anon,authenticated;
create trigger platform_reset_developer_guard before insert or update or delete on public.developer_accounts
for each row execute function private.guard_developer_reset_changes();
