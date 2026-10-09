import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import assert from 'node:assert/strict';
const migration=await readFile(new URL('../../migrations/20261009120210_quiz_play_until_six.sql',import.meta.url),'utf8');
const actor='00000000-0000-4000-8000-000000000001';
async function fixture(){
 const db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create schema auth;create schema private;create schema cron;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function public.grace_connect_leaderboard_church_id() returns text language sql as $$select 'church'::text$$;
 create function private.display_first_name(text) returns text language sql as $$select split_part($1,' ',1)$$;
 create function private.ranking_identity_visible(text,text) returns boolean language sql as $$select true$$;
 create table cron.job(jobid bigint,jobname text,schedule text);
 insert into cron.job values(1,'daily-bible-quiz-monthly-winners','5 5 1 * *');
 create function cron.alter_job(bigint,schedule text) returns void language sql as $$update cron.job set schedule=$2 where jobid=$1$$;
 create table public.users(id uuid,uid text,"displayName" text,"fullName" text,"photoUrl" text);
 create table public.user_blocks(blocker_id text,blocked_user_id text);
 create table public.daily_bible_quizzes(id uuid primary key,quiz_date date,status text,available_at timestamptz,expires_at timestamptz);
 create table public.quiz_attempts(id uuid,quiz_id uuid references daily_bible_quizzes(id),member_id uuid,status text,total_score int,correct_answers int,total_response_time_ms bigint,church_id text,church_id_at_attempt text,completed_at timestamptz);
 ${migration}
 insert into public.users values('${actor}','${actor}','Test Member','Test Member',null);
 select set_config('request.jwt.claim.sub','${actor}',false);
 insert into public.daily_bible_quizzes values
 ('00000000-0000-4000-8000-000000000010','2026-10-31','published','2026-10-31T12:00:00Z','2026-11-01T12:00:00Z'),
 ('00000000-0000-4000-8000-000000000011','2026-11-01','published','2026-11-01T12:00:00Z','2026-11-02T12:00:00Z');
 insert into public.quiz_attempts values
 ('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000010','${actor}','completed',100,5,25000,'church','church','2026-11-01T10:30:00Z'),
 ('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011','${actor}','completed',80,4,35000,'church','church','2026-11-01T13:30:00Z');`);
 return db;
}
test('quizzes stay selectable after midnight, close at 6, and awards wait until 6:05',async()=>{
 const db=await fixture();try{
  const open=async(time)=>(await db.query(`select quiz_date::text from daily_bible_quizzes where status='published' and available_at <= $1::timestamptz and expires_at > $1::timestamptz`,[time])).rows.map(r=>r.quiz_date);
  assert.deepEqual(await open('2026-11-01T05:00:00Z'),['2026-10-31']);
  assert.deepEqual(await open('2026-11-01T10:59:59.999Z'),['2026-10-31']);
  assert.deepEqual(await open('2026-11-01T11:00:00Z'),[]);
  assert.deepEqual(await open('2026-11-01T12:00:00Z'),['2026-11-01']);
  assert.equal((await db.query('select schedule from cron.job')).rows[0].schedule,'5 11 1 * *');
  await assert.rejects(db.exec(`update daily_bible_quizzes set available_at='2026-11-05T12:00:00Z'`),/open before/);
 }finally{await db.close();}
});
test('church and global scores use the quiz month despite an overnight completion',async()=>{
 const db=await fixture();try{
  for(const scope of ['church','global'])for(const [month,points] of [['2026-10',100],['2026-11',80]]){
   const row=(await db.query('select public.list_quiz_ranking($1,$2,25) as board',[scope,month])).rows[0].board;
   assert.equal(row.entries.length,1);assert.equal(row.entries[0].total_score,points);assert.equal(row.viewer.total_score,points);
   assert.equal(new Date(row.next_month_at).getUTCHours(),11);
  }
  await db.exec('set role anon');
  await assert.rejects(db.query("select public.list_quiz_ranking('global','2026-10',25)"),/permission denied/);
 }finally{await db.close();}
});
