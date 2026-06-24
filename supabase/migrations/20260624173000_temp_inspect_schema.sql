create or replace function public.inspect_table_columns(t_name text)
returns table(column_name text, data_type text)
language sql security definer as $$
  select column_name::text, data_type::text
  from information_schema.columns
  where table_schema = 'public' and table_name = t_name;
$$;

create or replace function public.inspect_auth_triggers()
returns table(tgname text, def text)
language sql security definer as $$
  select tgname::text, pg_get_triggerdef(oid)::text
  from pg_trigger
  where tgrelid = 'auth.users'::regclass and not tgisinternal;
$$;
