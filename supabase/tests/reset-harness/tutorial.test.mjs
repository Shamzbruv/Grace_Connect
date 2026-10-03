import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const migration = await readFile(new URL('../../migrations/20261002025212_user_tutorial_progress.sql', import.meta.url), 'utf8');
const a='00000000-0000-4000-8000-000000000001',b='00000000-0000-4000-8000-000000000002';
async function fixture(){
 const db=new PGlite();
 await db.exec(`create role anon; create role authenticated; create role service_role; create schema auth; create schema private;
 create table auth.users(id uuid primary key);
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema public,auth to authenticated,anon;
 insert into auth.users values('${a}');
 begin; ${migration} commit;
 insert into auth.users values('${b}');
 set role authenticated; select set_config('request.jwt.claim.sub','${a}',false);`);
 return db;
}
async function sync(db,g=1,enabled=false,dirty=false,progress=[]){return (await db.query('select public.sync_user_tutorials($1,$2,$3,$4::jsonb) as state',[g,enabled,dirty,JSON.stringify(progress)])).rows[0].state;}
const item=(screen,g=2,status='completed')=>({screen_id:screen,generation:g,tutorial_version:1,status,step_reached:2});
test('existing accounts stay off, new signups default on; RLS and grants isolate every account',async()=>{
 const db=await fixture();try{
 assert.equal((await sync(db)).enabled,false);
 assert.equal((await db.query('select * from public.user_tutorial_settings')).rows.length,1);
 await assert.rejects(db.query(`insert into public.user_tutorial_progress values('${b}',1,'inbox',1,'completed',1,null,now())`),/row-level security/);
 assert.equal((await db.query(`update public.user_tutorial_settings set enabled=true where user_id='${b}' returning *`)).rows.length,0);
 await db.exec(`select set_config('request.jwt.claim.sub','${b}',false)`);
 assert.equal((await sync(db)).enabled,true);
 assert.equal((await db.query('select * from public.user_tutorial_progress')).rows.length,0);
 await db.exec('reset role; set role anon');await assert.rejects(sync(db),/permission denied/);
 await db.exec("reset role; set role authenticated; select set_config('request.jwt.claim.sub','',false)");
 await assert.rejects(sync(db),/Authentication required/);
 }finally{await db.close();}
});
test('offline progress unions; stale devices cannot undo restart, disable or completed history',async()=>{
 const db=await fixture();try{
 let s=await sync(db,2,true,true,[item('community_feed')]);assert.equal(s.enabled,true);assert.equal(s.generation,2);
 s=await sync(db,2,true,false,[item('inbox')]);assert.equal(s.progress.length,2);
 s=await sync(db,2,true,false,[item('inbox',2,'dismissed')]);assert.equal(s.progress.find(p=>p.screen_id==='inbox').status,'completed');
 s=await sync(db,2,false,true);assert.equal(s.enabled,false);
 s=await sync(db,2,true,true);assert.equal(s.enabled,false);
 s=await sync(db,3,true,true);assert.equal(s.enabled,true);assert.equal(s.progress.length,0);
 s=await sync(db,2,false,true,[item('events')]);assert.equal(s.generation,3);assert.equal(s.enabled,true);assert.equal(s.progress.length,0);
 assert.equal((await db.query('select count(*)::int as count from public.user_tutorial_progress')).rows[0].count,3);
 await assert.rejects(sync(db,3,true,false,[item('future',4)]),/cannot precede/);
 await assert.rejects(sync(db,3,true,false,[item('invalid/name',3)]),/check constraint/);
 }finally{await db.close();}
});
