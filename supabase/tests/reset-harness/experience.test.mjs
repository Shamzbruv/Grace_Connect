import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import assert from 'node:assert/strict';
const migration=await readFile(new URL('../../migrations/20261002212722_app_experience_surveys.sql',import.meta.url),'utf8');
const a='00000000-0000-4000-8000-000000000001',b='00000000-0000-4000-8000-000000000002';
const device='10000000-0000-4000-8000-000000000001';
async function fixture(){const db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;create schema private;
create table auth.users(id uuid primary key);create table public.users(id uuid primary key,"fullName" text,email text);
create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
create function public.current_developer_role() returns text language sql as $$select nullif(current_setting('app.developer_role',true),'')$$;
create function public.log_developer_action(text,text,text,jsonb) returns void language sql as $$select$$;
insert into auth.users values('${a}'),('${b}');insert into public.users values('${a}','A','a@example.test'),('${b}','B','b@example.test');
grant usage on schema public,auth to authenticated,anon;${migration}
set role authenticated;select set_config('request.jwt.claim.sub','${a}',false);`);return db;}
async function sync(db,seconds,action='sync',answer=null,event=crypto.randomUUID(),dev=device){return(await db.query('select public.sync_app_experience($1,$2,$3,$4,$5,$6) as result',[dev,seconds,action,event,answer,'android'])).rows[0].result;}
async function portal(db,action='list',user=a){return(await db.query('select public.developer_app_experience($1,$2) as result',[action,user])).rows[0].result;}
test('two-hour active usage is cumulative and idempotent; survey claims are exclusive',async()=>{
 const db=await fixture();try{
 assert.equal((await sync(db,7199)).eligible,false);assert.equal((await sync(db,7200)).eligible,true);
 assert.equal((await sync(db,7200)).state.active_seconds,7200);
 const claim=await sync(db,7200,'shown');assert.equal(claim.claimed,true);assert.equal(claim.state.next_prompt_seconds,14400);
 assert.equal((await sync(db,7200,'shown')).claimed,false);
 assert.equal((await sync(db,100,'sync',null,crypto.randomUUID(),'20000000-0000-4000-8000-000000000001')).state.active_seconds,7300);
 assert.equal((await sync(db,50,'sync',null,crypto.randomUUID(),'20000000-0000-4000-8000-000000000001')).state.active_seconds,7300);
 assert.equal((await sync(db,20000)).eligible,false); // Wall-clock repeat cooldown also applies.
 await assert.rejects(db.exec(`update public.app_experience_state set next_prompt_seconds=0`),/permission denied/);
 }finally{await db.close();}
});
test('yes/no are recorded separately from store opens; developer resend cannot bypass cooldown or answered state',async()=>{
 const db=await fixture();try{
 await sync(db,7200,'shown');await assert.rejects(portal(db),/Developer access required/);
 await db.exec("select set_config('app.developer_role','super_developer',false)");
 await portal(db,'resend');let state=(await portal(db)).entries[0];assert.equal(state.remaining_active_seconds,7200);assert.ok(state.resend_requested_at);
 await sync(db,7300);await portal(db,'resend');state=(await portal(db)).entries[0];assert.equal(state.next_prompt_seconds,14400); // Clicking twice does not postpone indefinitely.
 await sync(db,7300,'answered',false);assert.equal((await sync(db,7300,'store_opened')).state.response,false);
 const entries=(await portal(db)).entries;assert.equal(entries[0].review_submission_status,'Not available from the store');
 await assert.rejects(portal(db,'resend'),/Only unanswered/);
 await db.exec(`select set_config('request.jwt.claim.sub','${b}',false);select set_config('app.developer_role','',false)`);
 assert.equal((await db.query('select * from public.app_experience_state')).rows.length,0);
 await assert.rejects(portal(db),/Developer access required/);
 await db.exec('reset role;set role anon');await assert.rejects(sync(db,1),/permission denied/);
 }finally{await db.close();}
});
