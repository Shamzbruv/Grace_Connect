-- Remove events after their calendar day has passed so the app and database
-- stay aligned without leaving stale rows in Supabase.

create or replace function public.cleanup_past_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer := 0;
begin
  delete from public.events
  where "date" < date_trunc('day', now());

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.cleanup_past_events() to authenticated;
