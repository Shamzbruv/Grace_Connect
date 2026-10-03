-- Prepare one canonical question set per date and mirror it to each audience.
-- Include ALL audience histories when choosing Global's next set, so a local
-- history conflict never needs a separate church/global AI generation.
create or replace function public.get_blocked_daily_bible_quiz_fact_keys(p_church_id text,p_quiz_date date)
returns text[] language plpgsql stable security definer set search_path='' as $$
declare strict_mode boolean; history_days integer; keys text[];
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required'; end if;
 if nullif(trim(p_church_id),'') is null or p_quiz_date is null then raise exception 'Church and quiz date required'; end if;
 select coalesce(quiz_guarantee_unique,true),greatest(1,least(coalesce(relaxed_quiz_history_days,60),3650))
 into strict_mode,history_days from public.daily_content_generation_settings where id;
 if exists(select 1 from public.daily_bible_quiz_questions qq join public.daily_bible_quizzes q on q.id=qq.quiz_id
  where (q.status='scheduled' or q.first_published_at is not null) and cardinality(qq.fact_keys)=0
   and (q.church_id=p_church_id or p_church_id='grace_connect_global') and q.quiz_date<>p_quiz_date
   and (strict_mode or q.quiz_date between p_quiz_date-history_days and p_quiz_date+history_days))
 then raise exception 'Quiz uniqueness cannot verify malformed retained quiz history'; end if;
 select coalesce(array_agg(distinct fact_key order by fact_key),array[]::text[]) into keys
 from public.daily_bible_quiz_questions qq join public.daily_bible_quizzes q on q.id=qq.quiz_id
 cross join lateral unnest(qq.fact_keys) as fact_key
 where (q.status='scheduled' or q.first_published_at is not null)
  and (q.church_id=p_church_id or p_church_id='grace_connect_global') and q.quiz_date<>p_quiz_date
  and (strict_mode or q.quiz_date between p_quiz_date-history_days and p_quiz_date+history_days);
 return keys;
end $$;
revoke all on function public.get_blocked_daily_bible_quiz_fact_keys(text,date) from public,anon,authenticated;
grant execute on function public.get_blocked_daily_bible_quiz_fact_keys(text,date) to service_role;

create table private.quiz_generation_leases(quiz_date date primary key,lease uuid not null,expires_at timestamptz not null);
alter table private.quiz_generation_leases enable row level security;
revoke all on private.quiz_generation_leases from public,anon,authenticated;
create function public.quiz_generation_lease(p_date date,p_release uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 if p_release is not null then
  delete from private.quiz_generation_leases where quiz_date=p_date and lease=p_release;return null;
 end if;
 insert into private.quiz_generation_leases(quiz_date,lease,expires_at) values(p_date,gen_random_uuid(),now()+interval '10 minutes')
 on conflict(quiz_date) do update set lease=excluded.lease,expires_at=excluded.expires_at
 where quiz_generation_leases.expires_at<now() returning lease into result;
 return result;
end $$;
revoke all on function public.quiz_generation_lease(date,uuid) from public,anon,authenticated;
grant execute on function public.quiz_generation_lease(date,uuid) to service_role;

create table private.daily_content_batch_jobs(
 content_date date primary key, stage text not null default 'word' check(stage in ('word','quiz')), status text not null default 'pending' check(status in ('pending','working','done','failed')),
 attempts integer not null default 0,lease uuid,lease_expires_at timestamptz,next_attempt_at timestamptz not null default now(),
 last_error text,completed_at timestamptz,updated_at timestamptz not null default now()
);
alter table private.daily_content_batch_jobs enable row level security;
revoke all on private.daily_content_batch_jobs from public,anon,authenticated;
create function private.queue_content_month(p_month date) returns integer language plpgsql security definer set search_path='' as $$
declare inserted integer;
begin
 insert into private.daily_content_batch_jobs(content_date)
 select day::date from generate_series(date_trunc('month',p_month)::date,(date_trunc('month',p_month)+interval '1 month - 1 day')::date,interval '1 day') day
 where day::date>(now() at time zone 'America/Jamaica')::date on conflict do nothing;
 get diagnostics inserted=row_count;return inserted;
end $$;
revoke all on function private.queue_content_month(date) from public,anon,authenticated;

create function public.daily_content_batch_worker(p_action text,p_date date default null,p_lease uuid default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job private.daily_content_batch_jobs;
begin
 -- Maintenance must not repopulate data while the one-time reset runs.
 if exists(select 1 from private.platform_reset_control where phase not in ('idle','complete')) then return null; end if;
 if p_action='claim' then
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
revoke all on function public.daily_content_batch_worker(text,date,uuid,text) from public,anon,authenticated;
grant execute on function public.daily_content_batch_worker(text,date,uuid,text) to service_role;

create function public.developer_content_batch(p_action text default 'status',p_month date default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare role_name text:=public.current_developer_role(); target date:=coalesce(p_month,(now() at time zone 'America/Jamaica')::date); rows jsonb;
begin
 if auth.uid() is null or role_name is null or role_name not in ('super_developer','support_developer','content_moderator','security_admin') then raise exception 'Developer access required' using errcode='42501';end if;
 if p_action in ('queue','retry') then
  if date_trunc('month',target)<date_trunc('month',now()) or target>current_date+62 then raise exception 'Choose this month or next month';end if;
  perform private.queue_content_month(target);
  if p_action='retry' then update private.daily_content_batch_jobs set status='pending',attempts=0,next_attempt_at=now(),last_error=null
   where status='failed' and date_trunc('month',content_date)=date_trunc('month',target);end if;
  perform public.log_developer_action('quiz_month_'||p_action,'content',target::text,'{}'::jsonb);
 elsif p_action<>'status' then raise exception 'Unknown action';end if;
 select coalesce(jsonb_agg(j order by j.content_date),'[]'::jsonb) into rows from private.daily_content_batch_jobs j
  where date_trunc('month',j.content_date)=date_trunc('month',target);
 return jsonb_build_object('month',to_char(target,'YYYY-MM'),'days',rows);
end $$;
revoke all on function public.developer_content_batch(text,date) from public,anon;
grant execute on function public.developer_content_batch(text,date) to authenticated;

-- Scheduling: dispatch only while work is actually queued. One date per worker
-- keeps Edge requests short; a month normally prepares in a single day.
select cron.schedule('monthly-daily-content-queue','0 6 25 * *',
 $$select private.queue_content_month((date_trunc('month',now() at time zone 'America/Jamaica')+interval '1 month')::date)$$);
select cron.schedule('monthly-daily-content-worker','*/2 * * * *',$cron$
 select net.http_post(
  url := coalesce((select decrypted_secret from vault.decrypted_secrets where name='grace_connect_project_url' limit 1),'https://nimgsgnkcvddomrgkawb.supabase.co')||'/functions/v1/prepare-monthly-daily-content',
  headers := jsonb_build_object('Content-Type','application/json','x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='daily_quiz_cron_secret' limit 1)),
  body := '{}'::jsonb,timeout_milliseconds:=240000)
 where exists(select 1 from private.daily_content_batch_jobs where attempts<3 and next_attempt_at<=now()
  and content_date>(now() at time zone 'America/Jamaica')::date
  and (status='pending' or (status='working' and lease_expires_at<now())));
 $cron$);
-- Queue only after the new worker and canonical generator are deployed.
