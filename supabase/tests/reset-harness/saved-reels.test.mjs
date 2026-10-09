import {PGlite} from '@electric-sql/pglite';import {readFile} from 'node:fs/promises';import {test} from 'node:test';import assert from 'node:assert/strict';
const migration=await readFile(new URL('../../migrations/20261009000134_saved_reel_details.sql',import.meta.url),'utf8');
test('Saved resolves old reel records, limits ownership, and redacts unavailable content',async()=>{
 const db=new PGlite();try{await db.exec(`create role anon;create role authenticated;create schema auth;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table public.social_saved_items(id int,user_id text,entity_type text,entity_id text,metadata jsonb default '{}',created_at timestamptz default now());
 alter table public.social_saved_items enable row level security;create policy own on public.social_saved_items for select to authenticated using(user_id=auth.uid()::text);
 create table public.fixture_reels(id uuid,available boolean);
 -- Existing detail RPC owns visibility/blocking checks; model an unavailable result here.
 create function public.get_reel_grace_detail(uuid) returns jsonb language sql as $$select jsonb_build_object('author_name','Author','caption','An encouragement') from public.fixture_reels where id=$1 and available$$;
 insert into public.fixture_reels values('00000000-0000-4000-8000-000000000010',true);
 insert into public.social_saved_items(id,user_id,entity_type,entity_id,metadata) values
 (1,'00000000-0000-4000-8000-000000000001','reel','00000000-0000-4000-8000-000000000010','{}'),
 (2,'00000000-0000-4000-8000-000000000002','reel','00000000-0000-4000-8000-000000000010','{}'),
 (3,'00000000-0000-4000-8000-000000000001','community_post','post','{"title":"Saved post"}');
 ${migration} grant usage on schema public,auth to authenticated,anon;grant select on public.social_saved_items,public.fixture_reels to authenticated;
 select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);set role authenticated;`);
 const read=async()=>Object.values((await db.query('select public.get_my_saved_items()')).rows[0])[0];
 let rows=await read();assert.equal(rows.length,2);assert.equal(rows.find(r=>r.entity_type==='reel').metadata.title,'Reel by Author');assert.equal(rows.find(r=>r.entity_type==='reel').is_available,true);
 assert.equal(rows.find(r=>r.entity_type==='community_post').metadata.title,'Saved post');
 await db.exec('reset role;update public.fixture_reels set available=false;set role authenticated');rows=await read();
 const hidden=rows.find(r=>r.entity_type==='reel');assert.equal(hidden.is_available,false);assert.equal(hidden.metadata.subtitle,'');assert.ok(!JSON.stringify(hidden).includes('An encouragement'));
 await db.exec('reset role;set role anon');await assert.rejects(read(),/permission denied/);
 }finally{await db.close();}
});
