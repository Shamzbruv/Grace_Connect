import {PGlite} from '@electric-sql/pglite';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import assert from 'node:assert/strict';
const migration=await readFile(new URL('../../migrations/20261009000136_fygaro_owner_configuration.sql',import.meta.url),'utf8');
const owner='00000000-0000-4000-8000-000000000001',other='00000000-0000-4000-8000-000000000002';
const config={button_url:'https://www.fygaro.com/en/pb/example-button',key_id:'example-key-id',secret_key:'fixture-checkout-secret',same_webhook_key:true,enabled:true};
async function fixture(){const db=new PGlite();await db.exec(`
create role anon;create role authenticated;create role service_role;create schema private;create schema vault;create schema auth;
create table auth.users(id uuid primary key,email text);insert into auth.users values('${owner}','owner@example.test'),('${other}','support@example.test');
create table public.developer_accounts(user_id uuid,email text,status text,developer_role text);insert into public.developer_accounts values('${owner}','owner@example.test','active','super_developer'),('${other}','support@example.test','active','support_developer');
create table public.audit(data jsonb);
create function public.log_developer_action(text,text,text,jsonb) returns void language sql as $$insert into public.audit values($4)$$;
-- Vault stand-in for isolated behavior tests; production uses encrypted Vault.
create table vault.secrets(id uuid primary key default gen_random_uuid(),secret text,name text unique,description text);
create view vault.decrypted_secrets as select id,name,secret as decrypted_secret from vault.secrets;
create function vault.create_secret(text,text,text) returns uuid language sql as $$insert into vault.secrets(secret,name,description) values($1,$2,$3) returning id$$;
create function vault.update_secret(uuid,text) returns void language sql as $$update vault.secrets set secret=$2 where id=$1$$;
${migration}
grant usage on schema public to anon,authenticated,service_role;`);return db;}
async function one(db,sql,params=[]){return Object.values((await db.query(sql,params)).rows[0])[0];}
async function save(db,c=config,actor=owner){return one(db,"select public.fygaro_owner_settings($1,'save',$2)",[actor,c]);}
test('only the verified owner can configure payments; browser roles cannot read secrets',async()=>{const db=await fixture();try{
 for(const role of ['anon','authenticated']){await db.exec('set role '+role);await assert.rejects(save(db),/permission denied/);await assert.rejects(one(db,'select public.fygaro_runtime_configuration()'),/permission denied/);await db.exec('reset role');}
 await db.exec('set role service_role');await assert.rejects(save(db,config,other),/Only the platform owner/);
 const status=await save(db);assert.equal(status.enabled,true);assert.equal(status.has_secret,true);assert.ok(!JSON.stringify(status).includes(config.secret_key));
 const runtime=await one(db,'select public.fygaro_runtime_configuration()');assert.equal(runtime.credentials.secret_key,config.secret_key);
 await db.exec('reset role');assert.deepEqual((await db.query('select data from public.audit')).rows,[{data:{enabled:true}}]);
 }finally{await db.close();}});
test('blank secrets preserve credentials, pause is explicit, and invalid changes roll back',async()=>{const db=await fixture();try{
 await db.exec('set role service_role');await save(db);
 const paused=await save(db,{...config,secret_key:'',enabled:false});assert.equal(paused.enabled,false);
 assert.equal((await one(db,'select public.fygaro_runtime_configuration()')).credentials.secret_key,config.secret_key);
 for(const button_url of ['https://fygaro.com.evil.test/en/pb/x','http://www.fygaro.com/en/pb/x','https://user:pass@fygaro.com/en/pb/x','https://fygaro.com/en/pb/x?jwt=bad'])await assert.rejects(save(db,{...config,button_url}),/HTTPS payment-button/);
 await assert.rejects(save(db,{...config,key_id:'new-key-identifier',secret_key:''}),/matching secret/);
 assert.equal((await one(db,'select public.fygaro_runtime_configuration()')).enabled,false);
 }finally{await db.close();}});
test('webhook key rotation keeps the prior credential for seven days',async()=>{const db=await fixture();try{
 await db.exec('set role service_role');await save(db);await save(db,{...config,same_webhook_key:false,webhook_key_id:'new-hook-identifier',webhook_secret_key:'fixture-hook-secret'});
 const runtime=await one(db,'select public.fygaro_runtime_configuration()');
 assert.equal(runtime.credentials.previous_webhook_key_id,config.key_id);
 assert.equal(runtime.credentials.previous_webhook_secret_key,config.secret_key);
 assert.ok(Date.parse(runtime.credentials.previous_webhook_expires_at)>Date.now()+6*86400000);
 }finally{await db.close();}});
