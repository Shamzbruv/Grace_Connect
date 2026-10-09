import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import assert from 'node:assert/strict';

// In-memory Postgres only. This harness has no network client or production URL.
const migration = (await readFile(new URL('../../migrations/20261001021711_developer_operations_and_one_time_reset.sql', import.meta.url), 'utf8')).split('-- Scheduling')[0];
const guardCompletion = await readFile(new URL('../../migrations/20261001111928_platform_reset_write_guard_completion.sql', import.meta.url), 'utf8');
const owner = '00000000-0000-4000-8000-000000000001';
const member = '00000000-0000-4000-8000-000000000002';
async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role; create role supabase_auth_admin;
    create schema private; create schema auth; create schema storage; create schema cron; create schema vault;
    create table auth.users(id uuid primary key,email text,encrypted_password text default 'untouched-hash');
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create table public.users(id uuid primary key,uid text,email text,"fullName" text,"displayName" text,"isDeveloper" boolean,"accountState" text,roles text[],"defaultRole" text,"placeId" text,"placeName" text);
    create table public.developer_accounts(id uuid primary key default gen_random_uuid(),user_id uuid,email text,developer_role text,status text,created_at timestamptz default now(),last_login_at timestamptz);
    create table public.churches(id text primary key,name text);
    create table public.posts(id int primary key,church_id text references public.churches,author_id uuid references auth.users, image_url text); create table public.comments(id int primary key,post_id int references public.posts on delete cascade);
    create table public.bible_book_catalog(id int); create table public.denominations(id int);
    create table public.policy_documents(id int); create table public.app_feature_flags(id int);
    create table public.daily_content_generation_settings(updated_by uuid references auth.users on delete set null);
    create table public.quote_backgrounds(id uuid primary key default gen_random_uuid(),file_name text);
    create table public.media_cleanup_queue(bucket_id text,object_path text,primary key(bucket_id,object_path));
    create table public.reel_media_cleanup_jobs(completed_at timestamptz);
    create table public.reels(id uuid primary key default gen_random_uuid(),moderation_status text,deleted_at timestamptz,author_church_id text,video_object_key text,poster_object_key text);
    create table public.church_billing_events(id int); create table public.church_checkout_sessions(id int);
    create table storage.objects(bucket_id text,name text,owner_id text);
    create table cron.job(jobid int,jobname text,active boolean);
    create table cron.job_run_details(jobid int,runid int,status text,end_time timestamptz);
    create table vault.decrypted_secrets(name text);
    create function public.current_developer_role() returns text language sql as $$select 'super_developer'::text$$;
    create function public.log_developer_action(text,text,text,jsonb) returns void language sql as $$select$$;
    create policy "developers manage quote backgrounds" on public.quote_backgrounds using(true) with check(true);
    create policy "developers write quote backgrounds" on storage.objects for insert with check(true);
    create policy "developers update quote backgrounds" on storage.objects for update using(true) with check(true);
    create policy "developers delete quote backgrounds" on storage.objects for delete using(true);
    insert into auth.users(id,email) values('${owner}','owner@example.test'),('${member}','member@example.test');
    insert into public.users(id,uid,email,"fullName","displayName") select id,id::text,email,'Name','Name' from auth.users;
    insert into public.developer_accounts(user_id,email,developer_role,status) values('${owner}','owner@example.test','super_developer','active'),('${member}','member@example.test','support_developer','active');
    insert into public.churches values('1','Other Church'); insert into public.posts values(1,'1',null,null);
    insert into public.bible_book_catalog values(1); insert into public.denominations values(1);
    insert into public.policy_documents values(1); insert into public.app_feature_flags values(1);
    insert into public.daily_content_generation_settings values('${member}');
    insert into storage.objects values('images','old.jpg',null);
    grant usage on schema public,auth,storage to authenticated,anon,service_role;
    grant insert,update,select,delete on public.posts,public.churches,public.users,public.developer_accounts to authenticated;
    grant insert,select on auth.users,storage.objects to authenticated;
    grant usage on schema auth to supabase_auth_admin;
    grant delete,select on auth.users to supabase_auth_admin;
  `);
  await db.exec(migration);
  await db.exec(guardCompletion);
  const tutorials = await readFile(new URL('../../migrations/20261002025212_user_tutorial_progress.sql', import.meta.url), 'utf8');
  await db.exec('begin;'+tutorials+'commit;');
  const surveys=await readFile(new URL('../../migrations/20261002212722_app_experience_surveys.sql',import.meta.url),'utf8');
  await db.exec(surveys);
  await db.exec(await readFile(new URL('../../migrations/20261009001032_preserve_play_review_on_reset.sql',import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../../migrations/20261009001529_optimize_review_reset_dependencies.sql',import.meta.url),'utf8'));
  return db;
}
async function value(db, sql) { return Object.values((await db.query(sql)).rows[0])[0]; }
async function asRole(db, role, sql) {
  await db.exec(`set role ${role}`);
  try { return await value(db,sql); } finally { await db.exec('reset role'); }
}

const review='00000000-0000-4000-8000-000000000003';
const seed=async db=>db.exec(`
 insert into auth.users(id,email) values('${review}','review@example.test');
 insert into public.users(id,uid,email,"placeId") values('${review}','${review}','review@example.test','review-church');
 insert into public.churches values('review-church','Review Church');
 insert into public.posts values(2,'review-church','${review}','https://example.test/storage/v1/object/public/images/shared.jpg');
 insert into public.comments values(1,1),(2,2);
 insert into public.reels(moderation_status,author_church_id,video_object_key,poster_object_key) values('approved','review-church','reels/review/video.mp4','reels/review/poster.jpg'),('approved','1','reels/other/video.mp4',null);
 insert into storage.objects values('images','shared.jpg',null),('images','review-avatar.jpg','${review}');
`);
test('review protection blocks reset until valid accounts/church are configured; no password is touched',async()=>{
 const db=await fixture();try{
 const rpc=sql=>asRole(db,'service_role',sql);
 assert.equal((await rpc(`select public.platform_operations_status('${owner}')`)).reset.can_start,false);
 await assert.rejects(rpc(`select public.platform_reset_begin('${owner}')`),/Configure and verify/);
 assert.equal(await value(db,'select consumed_at from private.platform_reset_control'),null);
 await seed(db);
 await assert.rejects(rpc(`select public.platform_reset_protect_review('${member}',array['review@example.test'],array['review-church'])`),/Only the platform owner/);
 await assert.rejects(rpc(`select public.platform_reset_protect_review('${owner}',array['missing@example.test'],array['review-church'])`),/existing account/);
 await assert.rejects(rpc(`select public.platform_reset_protect_review('${owner}',array['review@example.test'],array['1'])`),/belong/);
 await rpc(`select public.platform_reset_protect_review('${owner}',array['review@example.test'],array['review-church'])`);
 const status=await rpc(`select public.platform_operations_status('${owner}')`);
 assert.equal(status.reset.can_start,true);assert.deepEqual(status.reset.review_protection.review_emails,['review@example.test']);
 assert.equal(await value(db,`select encrypted_password from auth.users where id='${review}'`),'untouched-hash');
 for(const role of ['anon','authenticated']) await assert.rejects(asRole(db,role,`select public.platform_reset_protect_review('${owner}',array['review@example.test'],array['review-church'])`),/permission denied/);
 await assert.rejects(rpc(`select private.platform_reset_begin_legacy('${owner}')`),/permission denied/);
 }finally{await db.close()}
});
test('full staged reset keeps review church, credentials, child data and media; removes unrelated content once',async()=>{
 const db=await fixture();try{
 const rpc=sql=>asRole(db,'service_role',sql);await seed(db);
 // This essential setting should not accidentally preserve an unrelated author.
 await db.exec('update public.daily_content_generation_settings set updated_by=null');
 await rpc(`select public.platform_reset_protect_review('${owner}',array['review@example.test'],array['review-church'])`);
 await rpc(`select public.platform_reset_begin('${owner}')`);
 const job=await rpc("select public.platform_reset_worker('claim')");const call=c=>rpc(`select public.platform_reset_worker('${c}','${job.lease}')`);
 await call('purge');
 assert.deepEqual((await db.query('select id from public.churches')).rows,[{id:'review-church'}]);
 assert.deepEqual((await db.query('select id from public.posts')).rows,[{id:2}]);
 assert.deepEqual((await db.query('select id from public.comments')).rows,[{id:2}]);
 assert.equal(await value(db,`select "placeId" from public.users where id='${review}'`),'review-church');
 assert.equal(await value(db,`select encrypted_password from auth.users where id='${review}'`),'untouched-hash');
 assert.deepEqual(await call('storage_batch'),[{bucket:'images',path:'old.jpg'}]);
 await assert.rejects(call('advance'),/Storage cleanup/);
 await db.exec("delete from storage.objects where name='old.jpg'");await call('advance');
 assert.deepEqual(await rpc(`select public.platform_reset_filter_r2_keys(array['reels/review/video.mp4','reels/review/poster.jpg','reels/other/video.mp4'],'${job.lease}')`),['reels/other/video.mp4']);
 await rpc(`select public.platform_reset_worker('r2_cursor','${job.lease}','reels/review/video.mp4')`);
 assert.equal((await call('advance')).waiting_for_uploads,true);
 assert.equal(await value(db,'select r2_after from private.platform_reset_control'),null);
 await db.exec("update private.platform_reset_control set consumed_at=now()-interval '17 minutes'");await call('advance');
 assert.deepEqual(await call('account_batch'),[member]);
 await assert.rejects(call('advance'),/Account cleanup/);
 await db.exec(`set session authorization supabase_auth_admin; delete from auth.users where id='${member}'; set session authorization postgres;reset role;`);
 await call('advance');
 assert.equal(await value(db,'select phase from private.platform_reset_control'),'complete');
 assert.equal(await value(db,'select count(*)::int from storage.objects'),2);
 assert.equal(await value(db,'select count(*)::int from auth.users'),2);
 await assert.rejects(rpc(`select public.platform_reset_begin('${owner}')`),/already been used/);
 assert.equal(await call('release'),null);
 }finally{await db.close()}
});
