-- Only invoke Storage cleanup when there is work, and allow enough time for
-- the bounded batch of Storage API requests to finish.
select cron.schedule('graceconnect-media-retention','22 * * * *',$job$
  select net.http_post(
    url:='https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/cleanup-retained-media',
    headers:=jsonb_build_object('Content-Type','application/json','x-cron-secret',
      (select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
    body:='{}'::jsonb,
    timeout_milliseconds:=60000
  ) where exists (select 1 from public.list_retention_media_candidates(1));
$job$);

-- These extension-managed log tables were not receiving regular vacuum or
-- analyze despite accumulating months of writes. Standard VACUUM permits
-- normal queries and writes, and makes deleted pages available for reuse.
-- Run separately at 03:43 / 03:47 Jamaica time, away from the other jobs.
select cron.schedule('graceconnect-job-history-vacuum','43 8 * * *','VACUUM (ANALYZE) cron.job_run_details;');
select cron.schedule('graceconnect-http-response-vacuum','47 8 * * *','VACUUM (ANALYZE) net._http_response;');
