import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import assert from 'node:assert/strict';
const migration=await readFile(new URL('../../migrations/20261009120218_daily_quote_likes.sql',import.meta.url),'utf8');
const user1='00000000-0000-4000-8000-000000000001', user2='00000000-0000-4000-8000-000000000002', quote='00000000-0000-4000-8000-000000000010';
async function fixture(){const db=new PGlite();await db.exec(`
 create role anon;create role authenticated;create schema auth;create schema private;
 create table auth.users(id uuid primary key);
 insert into auth.users values('${user1}'),('${user2}');
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table private.platform_reset_control(singleton boolean primary key,phase text);
 insert into private.platform_reset_control values(true,'idle');
 create table public.daily_motivations(id uuid primary key,publish_date date,title text,message text,scripture_reference text,is_published boolean,status text);
 insert into public.daily_motivations values('${quote}',current_date-1,'Hope','Keep trusting God.','Psalms 23:1',true,'published');
 ${migration}
 grant usage on schema public,auth to anon,authenticated;
 select set_config('request.jwt.claim.sub','${user1}',false);set role authenticated;`);return db;}
async function react(db,liked){return (await db.query('select public.set_daily_motivation_like($1,$2) as result',[quote,liked])).rows[0].result;}
test('likes/unlikes are idempotent per account and public totals match both members',async()=>{
 const db=await fixture();try{
  assert.deepEqual(await react(db,true),{motivation_id:quote,liked:true,like_count:1});
  assert.equal((await react(db,true)).like_count,1);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[user2]);
  assert.equal((await react(db,true)).like_count,2);
  assert.equal((await react(db,false)).like_count,1);
  assert.equal((await react(db,false)).like_count,1);
  await assert.rejects(db.query('select * from private.daily_motivation_likes'),/permission denied/);
  await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role anon");
  const widget=(await db.query('select public.get_daily_word_widget() as result')).rows[0].result;
  assert.equal(widget.like_count,1);assert.equal(widget.id,quote);assert.ok(!JSON.stringify(widget).includes(user1));
  await assert.rejects(react(db,true),/permission denied/);
 }finally{await db.close();}
});
test('drafts/future quotes stay hidden and reset freezes reactions while account cascades stay safe',async()=>{
 const db=await fixture();try{
  await react(db,true);
  await db.exec("reset role;update daily_motivations set is_published=false;set role authenticated");
  assert.equal((await db.query('select public.get_daily_word_widget() as result')).rows[0].result,null);
  await assert.rejects(react(db,true),/no longer available/);
  await db.exec("reset role;update daily_motivations set is_published=true,publish_date=current_date+1;set role authenticated");
  assert.equal((await db.query('select public.get_daily_word_widget() as result')).rows[0].result,null);
  await db.exec("reset role;update daily_motivations set publish_date=current_date-1;update private.platform_reset_control set phase='accounts';set role authenticated");
  await assert.rejects(react(db,true),/being reset/);
  await db.exec(`reset role;delete from auth.users where id='${user1}';`);
  assert.equal((await db.query('select like_count from private.daily_motivation_like_counts')).rows[0].like_count,0);
  await db.exec('delete from daily_motivations');
  assert.equal((await db.query('select count(*)::int n from private.daily_motivation_like_counts')).rows[0].n,0);
 }finally{await db.close();}
});
