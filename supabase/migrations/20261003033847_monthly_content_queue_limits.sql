-- A date within 62 days could otherwise enqueue a whole later month beyond
-- the generation API window. Permit precisely this month and next month.
create or replace function public.developer_content_batch(p_action text default 'status',p_month date default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare role_name text:=public.current_developer_role(); target date:=coalesce(p_month,(now() at time zone 'America/Jamaica')::date); rows jsonb;
begin
 if auth.uid() is null or role_name is null or role_name not in ('super_developer','support_developer','content_moderator','security_admin') then raise exception 'Developer access required' using errcode='42501';end if;
 if p_action in ('queue','retry') then
  if date_trunc('month',target) not in (date_trunc('month',now() at time zone 'America/Jamaica'),date_trunc('month',now() at time zone 'America/Jamaica')+interval '1 month') then raise exception 'Choose this month or next month';end if;
  perform private.queue_content_month(target);
  if p_action='retry' then update private.daily_content_batch_jobs set status='pending',attempts=0,next_attempt_at=now(),last_error=null
   where status='failed' and date_trunc('month',content_date)=date_trunc('month',target);end if;
  perform public.log_developer_action('quiz_month_'||p_action,'content',target::text,'{}'::jsonb);
 elsif p_action<>'status' then raise exception 'Unknown action';end if;
 select coalesce(jsonb_agg(j order by j.content_date),'[]'::jsonb) into rows from private.daily_content_batch_jobs j
  where date_trunc('month',j.content_date)=date_trunc('month',target);
 return jsonb_build_object('month',to_char(target,'YYYY-MM'),'days',rows);
end $$;

-- Quota rejections do not consume content retries or exhaust the entire month.
create or replace function public.daily_content_batch_worker(p_action text,p_date date default null,p_lease uuid default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job private.daily_content_batch_jobs; quota_limited boolean:=p_action='failed' and coalesce(p_error,'') like '[quota]%';
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
  update private.daily_content_batch_jobs set status=case when quota_limited then 'pending' when p_action='complete' then 'done' when p_action='word_ready' then 'pending' when attempts>=3 then 'failed' else 'pending' end,
   stage=case when p_action='word_ready' then 'quiz' else stage end,attempts=case when p_action='word_ready' then 0 when quota_limited then greatest(0,attempts-1) else attempts end,
   completed_at=case when p_action='complete' then now() end,last_error=left(p_error,500),
   next_attempt_at=case when p_action='word_ready' then now() when quota_limited then now()+interval '24 hours' else now()+interval '6 hours' end,lease=null,lease_expires_at=null,updated_at=now()
   where content_date=p_date and lease=p_lease and lease_expires_at>now() returning * into job;
  if not found then raise exception 'Batch lease expired';end if;
  if quota_limited then
   -- All dates share provider credentials. Pause the queue once instead of
   -- sending the same doomed AI request for every remaining date.
   update private.daily_content_batch_jobs set next_attempt_at=greatest(next_attempt_at,now()+interval '24 hours'),
    last_error=left(p_error,500),updated_at=now() where status='pending' and content_date>(now() at time zone 'America/Jamaica')::date;
  end if;
  return to_jsonb(job);
 end if;
 raise exception 'Unknown batch action';
end $$;

