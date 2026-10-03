import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';import {test} from 'node:test';import assert from 'node:assert/strict';
const sql=await readFile(new URL('../../migrations/20261002212724_monthly_shared_quiz_preparation.sql',import.meta.url),'utf8');
const recovery=await readFile(new URL('../../migrations/20261003025250_monthly_batch_retry_recovery.sql',import.meta.url),'utf8');
const bounds=await readFile(new URL('../../migrations/20261003033847_monthly_content_queue_limits.sql',import.meta.url),'utf8');
async function fixture(){const db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;create schema cron;
create function auth.role() returns text language sql as $$select current_setting('request.jwt.claim.role',true)$$;
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function public.current_developer_role() returns text language sql as $$select current_setting('app.developer_role',true)$$;
create function public.log_developer_action(text,text,text,jsonb) returns void language sql as $$select$$;
create function cron.schedule(text,text,text) returns integer language sql as $$select 1$$;
create table public.daily_content_generation_settings(id boolean primary key,quiz_guarantee_unique boolean,relaxed_quiz_history_days int);insert into public.daily_content_generation_settings values(true,true,60);
create table public.daily_bible_quizzes(id uuid primary key,church_id text,quiz_date date,status text,first_published_at timestamptz);
create table public.daily_bible_quiz_questions(quiz_id uuid,fact_keys text[]);
create table private.platform_reset_control(phase text);insert into private.platform_reset_control values('idle');${sql}${recovery}${bounds}
grant usage on schema public,auth to service_role,authenticated,anon;
select set_config('request.jwt.claim.role','service_role',false);`);return db;}
async function one(db,sql,params=[]){return Object.values((await db.query(sql,params)).rows[0])[0];}
test('canonical generation excludes every audience history but permits same-day mirroring',async()=>{const db=await fixture();try{
 await db.exec(`insert into public.daily_bible_quizzes values('00000000-0000-4000-8000-000000000001','church-a',current_date-2,'published',now()),('00000000-0000-4000-8000-000000000002','grace_connect_global',current_date,'scheduled',null);
 insert into public.daily_bible_quiz_questions values('00000000-0000-4000-8000-000000000001',array['historic-fact']),('00000000-0000-4000-8000-000000000002',array['today-fact']);set role service_role;`);
 assert.deepEqual(await one(db,"select public.get_blocked_daily_bible_quiz_fact_keys('grace_connect_global',current_date)"),['historic-fact']);
 assert.deepEqual(await one(db,"select public.get_blocked_daily_bible_quiz_fact_keys('church-a',current_date)"),['historic-fact']);
 const lease=await one(db,'select public.quiz_generation_lease(current_date)');assert.ok(lease);assert.equal(await one(db,'select public.quiz_generation_lease(current_date)'),null);
 await one(db,'select public.quiz_generation_lease(current_date,$1)',[lease]);assert.ok(await one(db,'select public.quiz_generation_lease(current_date)'));
 await db.exec('reset role;set role authenticated');await assert.rejects(one(db,'select public.quiz_generation_lease(current_date)'),/permission denied/);
 }finally{await db.close();}});
test('month queue resumes between stages, bounds retries and respects maintenance',async()=>{const db=await fixture();try{
 await one(db,"select private.queue_content_month((date_trunc('month',current_date)+interval '1 month')::date)");
 const count=await one(db,'select count(*)::int from private.daily_content_batch_jobs');assert.ok(count>=28&&count<=31);
 await one(db,"select private.queue_content_month((date_trunc('month',current_date)+interval '1 month')::date)");assert.equal(await one(db,'select count(*)::int from private.daily_content_batch_jobs'),count);
 await db.exec('set role service_role');const job=await one(db,"select public.daily_content_batch_worker('claim')");assert.equal(job.stage,'word');
 await assert.rejects(one(db,"select public.daily_content_batch_worker('word_ready',$1,gen_random_uuid())",[job.content_date]),/lease expired/);
 await one(db,"select public.daily_content_batch_worker('word_ready',$1,$2)",[job.content_date,job.lease]);
 const quiz=await one(db,"select public.daily_content_batch_worker('claim')");assert.equal(quiz.content_date,job.content_date);assert.equal(quiz.stage,'quiz');
 await one(db,"select public.daily_content_batch_worker('complete',$1,$2)",[quiz.content_date,quiz.lease]);
 await db.exec("reset role;update private.platform_reset_control set phase='data';set role service_role");assert.equal(await one(db,"select public.daily_content_batch_worker('claim')"),null);
 await db.exec('reset role;set role authenticated');await assert.rejects(one(db,"select public.developer_content_batch('queue',current_date)"),/Developer access required/);
 }finally{await db.close();}});
test('failed preparation backs off for six hours and stops after three attempts',async()=>{const db=await fixture();try{
 await db.exec("insert into private.daily_content_batch_jobs(content_date) values(current_date+1);set role service_role");
 for(let attempt=1;attempt<=3;attempt++){
  const job=await one(db,"select public.daily_content_batch_worker('claim')");assert.equal(job.attempts,attempt);
  const result=await one(db,"select public.daily_content_batch_worker('failed',$1,$2,'Temporary error')",[job.content_date,job.lease]);
  assert.equal(result.status,attempt===3?'failed':'pending');
  assert.ok(new Date(result.next_attempt_at)-new Date(result.updated_at)>=6*60*60*1000);
  assert.equal(await one(db,"select public.daily_content_batch_worker('claim')"),null);
  await db.exec("reset role;update private.daily_content_batch_jobs set next_attempt_at=now()-interval '1 second';set role service_role");
 }
 assert.equal(await one(db,"select public.daily_content_batch_worker('claim')"),null);
 }finally{await db.close();}});
test('a killed final worker becomes failed and a developer can explicitly retry',async()=>{const db=await fixture();try{
 await db.exec("insert into private.daily_content_batch_jobs(content_date,attempts) values(current_date+1,2);set role service_role");
 const job=await one(db,"select public.daily_content_batch_worker('claim')");assert.equal(job.attempts,3);
 await db.exec("reset role;update private.daily_content_batch_jobs set lease_expires_at=now()-interval '1 second';set role service_role");
 assert.equal(await one(db,"select public.daily_content_batch_worker('claim')"),null);
 await db.exec("reset role");assert.equal(await one(db,'select status from private.daily_content_batch_jobs'),'failed');
 await db.exec("set role authenticated;select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);select set_config('app.developer_role','super_developer',false)");
 const result=await one(db,"select public.developer_content_batch('retry',current_date+1)");
 const reset=result.days.find(day=>day.content_date===job.content_date);assert.equal(reset.status,'pending');assert.equal(reset.attempts,0);
 }finally{await db.close();}});

test('developer queue rejects months outside the complete preparation window',async()=>{const db=await fixture();try{
 await db.exec("set role authenticated;select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);select set_config('app.developer_role','super_developer',false)");
 await assert.rejects(one(db,"select public.developer_content_batch('queue',(date_trunc('month',now() at time zone 'America/Jamaica')+interval '2 months')::date)"),/this month or next month/);
 await assert.rejects(one(db,"select public.developer_content_batch('queue',(date_trunc('month',now() at time zone 'America/Jamaica')-interval '1 month')::date)"),/this month or next month/);
 const result=await one(db,"select public.developer_content_batch('queue',(date_trunc('month',now() at time zone 'America/Jamaica')+interval '1 month')::date)");assert.ok(result.days.length>=28);
 }finally{await db.close();}});
test('provider quota pauses all queued dates without consuming the final content retry',async()=>{const db=await fixture();try{
 await db.exec("insert into private.daily_content_batch_jobs(content_date,attempts) values(current_date+1,2),(current_date+2,0);set role service_role");
 const job=await one(db,"select public.daily_content_batch_worker('claim')");
 const failed=await one(db,"select public.daily_content_batch_worker('failed',$1,$2,'[quota] Wait for daily quota reset')",[job.content_date,job.lease]);
 assert.equal(failed.status,'pending');assert.equal(failed.attempts,2);
 assert.equal(await one(db,"select public.daily_content_batch_worker('claim')"),null);
 await db.exec('reset role');const rows=(await db.query('select * from private.daily_content_batch_jobs')).rows;
 assert.equal(rows.length,2);for(const row of rows){assert.ok(new Date(row.next_attempt_at)-new Date(row.updated_at)>=24*60*60*1000);assert.match(row.last_error,/quota/);}
 }finally{await db.close();}});
