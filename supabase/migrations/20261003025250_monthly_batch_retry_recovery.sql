create or replace function public.daily_content_batch_worker(p_action text,p_date date default null,p_lease uuid default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job private.daily_content_batch_jobs;
begin
 -- Maintenance must not repopulate data while the one-time reset runs.
 if exists(select 1 from private.platform_reset_control where phase not in ('idle','complete')) then return null; end if;
 if p_action='claim' then
  -- A terminated final attempt must become retryable from the portal rather
  -- than remain 'working' forever after its lease expires.
  update private.daily_content_batch_jobs
   set status='failed',lease=null,lease_expires_at=null,
    last_error=coalesce(last_error,'Worker timed out after three attempts.'),updated_at=now()
   where status='working' and attempts>=3 and lease_expires_at<now();
  select * into job from private.daily_content_batch_jobs
   where content_date>(now() at time zone 'America/Jamaica')::date and attempts<3 and next_attempt_at<=now()
    and (status='pending' or (status='working' and lease_expires_at<now()))
   order by content_date for update skip locked limit 1;
  if not found then return null;end if;
  update private.daily_content_batch_jobs set status='working',lease=gen_random_uuid(),lease_expires_at=now()+interval '10 minutes',attempts=attempts+1,updated_at=now()
   where content_date=job.content_date returning * into job;
  return to_jsonb(job);
 elsif p_action in ('word_ready','complete','failed') then
  update private.daily_content_batch_jobs set status=case when p_action='complete' then 'done' when p_action='word_ready' then 'pending' when attempts>=3 then 'failed' else 'pending' end,
   stage=case when p_action='word_ready' then 'quiz' else stage end,attempts=case when p_action='word_ready' then 0 else attempts end,
   completed_at=case when p_action='complete' then now() end,last_error=left(p_error,500),
   next_attempt_at=case when p_action='word_ready' then now() else now()+interval '6 hours' end,lease=null,lease_expires_at=null,updated_at=now()
   where content_date=p_date and lease=p_lease and lease_expires_at>now() returning * into job;
  if not found then raise exception 'Batch lease expired';end if;return to_jsonb(job);
 end if;
 raise exception 'Unknown batch action';
end $$;

-- Dispatch one recovery pass for an exhausted worker, even without pending work.
select cron.schedule('monthly-daily-content-worker','*/2 * * * *',$cron$
 select net.http_post(
  url := coalesce((select decrypted_secret from vault.decrypted_secrets where name='grace_connect_project_url' limit 1),'https://nimgsgnkcvddomrgkawb.supabase.co')||'/functions/v1/prepare-monthly-daily-content',
  headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
  body := '{}'::jsonb,timeout_milliseconds:=240000)
 where exists(select 1 from private.daily_content_batch_jobs where next_attempt_at<=now()
  and content_date>(now() at time zone 'America/Jamaica')::date
  and ((status='pending' and attempts<3) or (status='working' and lease_expires_at<now())));
 $cron$);
