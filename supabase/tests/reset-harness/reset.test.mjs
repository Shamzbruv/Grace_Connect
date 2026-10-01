import { PGlite } from '@electric-sql/pglite';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import assert from 'node:assert/strict';

// In-memory Postgres only. This harness has no network client or production URL.
const migration = (await readFile(new URL('../../migrations/20261001021711_developer_operations_and_one_time_reset.sql', import.meta.url), 'utf8')).split('-- Scheduling')[0];
const owner = '00000000-0000-4000-8000-000000000001';
const member = '00000000-0000-4000-8000-000000000002';
async function fixture() {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role; create role supabase_auth_admin;
    create schema private; create schema auth; create schema storage; create schema cron; create schema vault;
    create table auth.users(id uuid primary key,email text);
    create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    create table public.users(id uuid primary key,uid text,email text,"fullName" text,"displayName" text,"isDeveloper" boolean,"accountState" text,roles text[],"defaultRole" text);
    create table public.developer_accounts(id uuid primary key default gen_random_uuid(),user_id uuid,email text,developer_role text,status text,created_at timestamptz default now());
    create table public.churches(id int primary key);
    create table public.posts(id int primary key,church_id int references public.churches);
    create table public.bible_book_catalog(id int); create table public.denominations(id int);
    create table public.policy_documents(id int); create table public.app_feature_flags(id int);
    create table public.daily_content_generation_settings(updated_by uuid references auth.users on delete set null);
    create table public.quote_backgrounds(id uuid primary key default gen_random_uuid(),file_name text);
    create table public.media_cleanup_queue(bucket_id text,object_path text,primary key(bucket_id,object_path));
    create table public.reel_media_cleanup_jobs(completed_at timestamptz);
    create table public.reels(moderation_status text,deleted_at timestamptz);
    create table public.church_billing_events(id int); create table public.church_checkout_sessions(id int);
    create table storage.objects(bucket_id text,name text);
    create table cron.job(jobid int,jobname text,active boolean);
    create table cron.job_run_details(jobid int,runid int,status text,end_time timestamptz);
    create table vault.decrypted_secrets(name text);
    create function public.current_developer_role() returns text language sql as $$select 'super_developer'::text$$;
    create function public.log_developer_action(text,text,text,jsonb) returns void language sql as $$select$$;
    create policy "developers manage quote backgrounds" on public.quote_backgrounds using(true) with check(true);
    create policy "developers write quote backgrounds" on storage.objects for insert with check(true);
    create policy "developers update quote backgrounds" on storage.objects for update using(true) with check(true);
    create policy "developers delete quote backgrounds" on storage.objects for delete using(true);
    insert into auth.users values('${owner}','owner@example.test'),('${member}','member@example.test');
    insert into public.users(id,uid,email,"fullName","displayName") select id,id::text,email,'Name','Name' from auth.users;
    insert into public.developer_accounts(user_id,email,developer_role,status) values('${owner}','owner@example.test','super_developer','active'),('${member}','member@example.test','support_developer','active');
    insert into public.churches values(1); insert into public.posts values(1,1);
    insert into public.bible_book_catalog values(1); insert into public.denominations values(1);
    insert into public.policy_documents values(1); insert into public.app_feature_flags values(1);
    insert into public.daily_content_generation_settings values('${member}');
    insert into storage.objects values('images','old.jpg');
    grant usage on schema public,auth,storage to authenticated,anon,service_role;
    grant insert,update,select on public.posts,public.churches to authenticated;
    grant insert,select on auth.users,storage.objects to authenticated;
    grant usage on schema auth to supabase_auth_admin;
    grant delete,select on auth.users to supabase_auth_admin;
  `);
  await db.exec(migration);
  return db;
}
async function value(db, sql) { return Object.values((await db.query(sql)).rows[0])[0]; }
async function asRole(db, role, sql) {
  await db.exec(`set role ${role}`);
  try { return await value(db,sql); } finally { await db.exec('reset role'); }
}

test('installation preserves data; privileged calls reject ordinary roles and non-owner', async () => {
  const db = await fixture();
  try {
    assert.equal(await value(db,'select count(*)::int from public.users'),2);
    assert.equal(await value(db,'select phase from private.platform_reset_control'),'idle');
    for (const role of ['anon','authenticated']) {
      for (const sql of [`select public.platform_reset_begin('${owner}')`,`select public.platform_reset_worker('claim')`,`select public.platform_operations_status('${owner}')`]) {
        await assert.rejects(asRole(db,role,sql),/permission denied/);
      }
    }
    await assert.rejects(asRole(db,'service_role',`select public.platform_reset_begin('${member}')`),/Only the platform owner/);
    const status = await asRole(db,'service_role',`select public.platform_operations_status('${owner}')`);
    assert.equal(status.reset.can_start,true);
    assert.equal(status.reset.other_accounts,1);
    await db.exec('create table public.unreviewed_data(id int)');
    await assert.rejects(asRole(db,'service_role',`select public.platform_reset_begin('${owner}')`),/inventory needs review/);
  } finally { await db.close(); }
});

test('one-time reset freezes writes, resumes safely, preserves owner, and cannot be reused', async () => {
  const db = await fixture();
  try {
    const rpc = sql => asRole(db,'service_role',sql);
    await rpc(`select public.platform_reset_begin('${owner}')`);
    await assert.rejects(rpc(`select public.platform_reset_begin('${owner}')`),/already been used/);
    await db.exec(`select set_config('request.jwt.claim.sub','${member}',false)`);
    await assert.rejects(asRole(db,'authenticated','insert into public.posts values(2,1) returning id'),/being reset/);
    await assert.rejects(asRole(db,'authenticated',`insert into auth.users values(gen_random_uuid(),'new@example.test') returning id`),/being reset/);
    await assert.rejects(asRole(db,'authenticated',`insert into storage.objects values('images','new.jpg') returning name`),/being reset/);
    const job = await rpc("select public.platform_reset_worker('claim')");
    assert.equal(await rpc("select public.platform_reset_worker('claim')"),null);
    await assert.rejects(rpc("select public.platform_reset_worker('purge',gen_random_uuid())"),/lease expired/);
    const call = command => rpc(`select public.platform_reset_worker('${command}','${job.lease}')`);
    await call('purge');
    assert.equal(await value(db,'select count(*)::int from public.churches'),0);
    assert.equal(await value(db,'select count(*)::int from public.posts'),0);
    assert.deepEqual((await db.query('select id from public.users')).rows,[{id:owner}]);
    assert.deepEqual((await db.query('select user_id from public.developer_accounts')).rows,[{user_id:owner}]);
    for (const table of ['bible_book_catalog','denominations','policy_documents','app_feature_flags']) assert.equal(await value(db,`select count(*)::int from public.${table}`),1);
    assert.equal(await value(db,'select updated_by from public.daily_content_generation_settings'),null);
    assert.equal((await call('storage_batch')).length,1);
    await assert.rejects(call('advance'),/Storage cleanup is not finished/);
    await db.exec('delete from storage.objects'); // Simulates successful Storage API deletion in the local fixture only.
    await call('advance');
    assert.equal((await call('advance')).waiting_for_uploads,true);
    await db.exec("update private.platform_reset_control set consumed_at=now()-interval '17 minutes'");
    await call('advance');
    await assert.rejects(call('advance'),/Account or storage cleanup/);
    await db.exec(`set session authorization supabase_auth_admin; delete from auth.users where id='${member}'; set session authorization postgres; reset role;`);
    await call('advance');
    assert.equal(await value(db,'select phase from private.platform_reset_control'),'complete');
    assert.equal(await call('release'),null);
    await assert.rejects(rpc(`select public.platform_reset_begin('${owner}')`),/already been used/);
    await assert.rejects(asRole(db,'authenticated','insert into public.churches values(2) returning id'),/no longer active/);
    await db.exec(`select set_config('request.jwt.claim.sub','${owner}',false)`);
    assert.equal(await asRole(db,'authenticated','insert into public.churches values(2) returning id'),2);
  } finally { await db.close(); }
});

test('expired leases are reclaimed without reusing the reset', async () => {
  const db = await fixture();
  try {
    const rpc = sql => asRole(db,'service_role',sql);
    await rpc(`select public.platform_reset_begin('${owner}')`);
    const first = await rpc("select public.platform_reset_worker('claim')");
    await db.exec("update private.platform_reset_control set lease_until=now()-interval '1 second'");
    const second = await rpc("select public.platform_reset_worker('claim')");
    assert.notEqual(first.lease,second.lease);
    await assert.rejects(rpc(`select public.platform_reset_worker('purge','${first.lease}')`),/lease expired/);
    await rpc(`select public.platform_reset_worker('purge','${second.lease}')`);
    assert.equal(await value(db,'select phase from private.platform_reset_control'),'storage');
  } finally { await db.close(); }
});
