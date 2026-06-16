-- Run Grace Connect cleanup from Supabase itself so expired content is not
-- dependent on someone opening the app.

create extension if not exists pg_cron with schema extensions;

create or replace function public.run_graceconnect_daily_cleanup()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_stories integer := 0;
  vanishing_result jsonb := '{}'::jsonb;
  deleted_events integer := 0;
begin
  deleted_stories := public.cleanup_expired_community_stories();
  vanishing_result := public.cleanup_vanishing_content();
  deleted_events := public.cleanup_past_events();

  return jsonb_build_object(
    'deleted_stories', deleted_stories,
    'vanishing_content', vanishing_result,
    'deleted_events', deleted_events
  );
end;
$$;

grant execute on function public.run_graceconnect_daily_cleanup()
  to authenticated;

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'graceconnect-daily-cleanup'
  ) then
    perform cron.unschedule('graceconnect-daily-cleanup');
  end if;

  perform cron.schedule(
    'graceconnect-daily-cleanup',
    '15 7 * * *',
    'select public.run_graceconnect_daily_cleanup();'
  );
end;
$$;
