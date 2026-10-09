-- Installs protection only. Never starts a reset or changes account passwords.
create table private.platform_reset_review_protection (
 singleton boolean primary key default true check(singleton),
 user_ids uuid[] not null, church_ids text[] not null,
 configured_by uuid not null, configured_at timestamptz not null default now()
);
create table private.platform_reset_kept_rows (
 table_name text not null, row_key jsonb not null, row_data jsonb not null,
 primary key(table_name,row_key)
);
create table private.platform_reset_kept_media (
 provider text not null, bucket text not null default '', path text not null,
 primary key(provider,bucket,path)
);
alter table private.platform_reset_control add column r2_after text;
alter table private.platform_reset_review_protection enable row level security;
alter table private.platform_reset_kept_rows enable row level security;
alter table private.platform_reset_kept_media enable row level security;
revoke all on private.platform_reset_review_protection,private.platform_reset_kept_rows,private.platform_reset_kept_media from public,anon,authenticated;

create function private.reset_row_key(p_table regclass,p_row jsonb)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_object_agg(a.attname,p_row->a.attname),p_row)
 from pg_constraint c join unnest(c.conkey) k(n) on true
 join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.n
 where c.conrelid=p_table and c.contype='p'
$$;
revoke all on function private.reset_row_key(regclass,jsonb) from public,anon,authenticated;

create function private.prepare_review_reset(p_owner uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cfg private.platform_reset_review_protection%rowtype; t record; f record;
 changed integer; added integer; pass integer:=0; join_sql text; parent_name text;
begin
 select * into cfg from private.platform_reset_review_protection where singleton;
 if cfg.singleton is null or cardinality(cfg.user_ids)=0 or cardinality(cfg.church_ids)=0 then
   raise exception 'Configure and verify Google Play review accounts and their church before resetting.';
 end if;
 if exists(select 1 from unnest(cfg.user_ids) u(id) where not exists(select 1 from auth.users a join public.users p on p.id=a.id where a.id=u.id))
   or exists(select 1 from unnest(cfg.church_ids) c(id) where not exists(select 1 from public.churches p where p.id::text=c.id)) then
   raise exception 'A protected review account or church no longer exists. Update the protection settings.';
 end if;
 delete from private.platform_reset_kept_rows;
 delete from private.platform_reset_kept_media;
 -- Keep complete church data, including member profiles. Do not strand a review
 -- church by deleting accounts that its records and permissions depend on.
 for t in select table_name,preserve from private.platform_reset_tables loop
   execute format($q$insert into private.platform_reset_kept_rows
    select %L,private.reset_row_key(%L::regclass,to_jsonb(r)),to_jsonb(r) from public.%I r
    where %L::boolean
      or (%L='users' and to_jsonb(r)->>'id'=$1::text)
      or (%L='developer_accounts' and (to_jsonb(r)->>'user_id'=$1::text
        or lower(to_jsonb(r)->>'email')=(select lower(email) from auth.users where id=$1)))
      or (%L='churches' and to_jsonb(r)->>'id'=any($3))
      or (%L not in ('media_cleanup_queue','reel_media_cleanup_jobs') and exists(
        select 1 from jsonb_each_text(to_jsonb(r)) v where
         (v.key in ('church_id','churchId','placeId','author_church_id') and v.value=any($3))
         or (v.key in ('id','uid','user_id','userId','member_id','author_id','sender_id','recipient_id','created_by') and v.value=any($2))))
    on conflict do nothing$q$,t.table_name,'public.'||quote_ident(t.table_name),t.table_name,t.preserve,
       t.table_name,t.table_name,t.table_name,t.table_name) using p_owner,cfg.user_ids::text[],cfg.church_ids;
 end loop;
 insert into private.platform_reset_kept_rows
 select 'auth.users',jsonb_build_object('id',id),jsonb_build_object('id',id,'email',email)
 from auth.users where id=p_owner or id=any(cfg.user_ids);
 -- Reach a fixed point over actual database foreign keys. Keep child content of
 -- church objects, and every referenced parent. Never fan out from a user or an
 -- essential catalogue into unrelated content. Credentials remain in Auth.
 loop
   changed:=0; pass:=pass+1;
   if pass>100 then raise exception 'Review preservation dependencies could not be resolved.'; end if;
   for f in select c.*,n.nspname,p.relname parent,c1.relname child from pg_constraint c
     join pg_class c1 on c1.oid=c.conrelid join pg_namespace n1 on n1.oid=c1.relnamespace
     join pg_class p on p.oid=c.confrelid join pg_namespace n on n.oid=p.relnamespace
     where c.contype='f' and n1.nspname='public' and (n.nspname='public' or (n.nspname='auth' and p.relname='users'))
   loop
     if f.nspname='auth' and f.confdeltype='n' and exists(select 1 from private.platform_reset_tables where table_name=f.child and preserve) then continue; end if;
     parent_name:=case when f.nspname='auth' then 'auth.users' else f.parent end;
     select string_agg(format('p.%I = c.%I',pa.attname,ca.attname),' and ' order by k.i) into join_sql
      from generate_subscripts(f.conkey,1) k(i)
      join pg_attribute ca on ca.attrelid=f.conrelid and ca.attnum=f.conkey[k.i]
      join pg_attribute pa on pa.attrelid=f.confrelid and pa.attnum=f.confkey[k.i];
     execute format($q$insert into private.platform_reset_kept_rows
       select %L,private.reset_row_key(%L::regclass,to_jsonb(p)),%s
       from %I.%I p join public.%I c on %s
       join private.platform_reset_kept_rows kept on kept.table_name=%L and to_jsonb(c) @> kept.row_key
       on conflict do nothing$q$,parent_name,f.confrelid::regclass::text,
       case when f.nspname='auth' then 'jsonb_build_object(''id'',p.id,''email'',p.email)' else 'to_jsonb(p)' end,
       f.nspname,f.parent,f.child,join_sql,f.child);
     get diagnostics added=row_count; changed:=changed+added;
     if f.nspname='public' and f.parent not in ('users','developer_accounts')
       and not exists(select 1 from private.platform_reset_tables where table_name=f.parent and preserve)
       and f.child not in ('media_cleanup_queue','reel_media_cleanup_jobs') then
       execute format($q$insert into private.platform_reset_kept_rows
         select %L,private.reset_row_key(%L::regclass,to_jsonb(c)),to_jsonb(c)
         from public.%I c join public.%I p on %s
         join private.platform_reset_kept_rows kept on kept.table_name=%L and to_jsonb(p) @> kept.row_key
         on conflict do nothing$q$,f.child,f.conrelid::regclass::text,f.child,f.parent,join_sql,f.parent);
       get diagnostics added=row_count; changed:=changed+added;
     end if;
   end loop;
   -- Older app tables use text IDs / participant arrays without FK constraints.
   -- Preserve those referenced identities as well, without reading Auth secrets.
   insert into private.platform_reset_kept_rows
   select 'auth.users',jsonb_build_object('id',a.id),jsonb_build_object('id',a.id,'email',a.email)
   from auth.users a where exists(select 1 from private.platform_reset_kept_rows k,
     lateral jsonb_path_query(k.row_data,'$.** ? (@.type() == "string")') v(value)
     where k.table_name<>'auth.users'
       and not exists(select 1 from private.platform_reset_tables inventory where inventory.table_name=k.table_name and inventory.preserve)
       and v.value #>> '{}' = a.id::text)
   on conflict do nothing;
   get diagnostics added=row_count; changed:=changed+added;
   -- Auth dependencies need their public profiles too, without preserving all
   -- unrelated posts written by those authors.
   insert into private.platform_reset_kept_rows
   select 'users',jsonb_build_object('id',u.id),to_jsonb(u) from public.users u
   join private.platform_reset_kept_rows k on k.table_name='auth.users' and k.row_key->>'id'=u.id::text
   on conflict do nothing;
   get diagnostics added=row_count; changed:=changed+added;
   exit when changed=0;
 end loop;
 -- Snapshot file references before deletion triggers run. Retain owned media,
 -- church folders, and public/signed URLs nested inside preserved metadata.
 insert into private.platform_reset_kept_media
 select 'storage',o.bucket_id,o.name from storage.objects o where
  exists(select 1 from private.platform_reset_kept_rows k where k.table_name='auth.users'
    and (k.row_key->>'id' in (to_jsonb(o)->>'owner_id',to_jsonb(o)->>'owner',split_part(o.name,'/',1))))
  or split_part(o.name,'/',1)=any(cfg.church_ids)
  or exists(select 1 from private.platform_reset_kept_rows k,
     lateral jsonb_path_query(k.row_data,'$.** ? (@.type() == "string")') s(value)
     where (s.value #>> '{}')=o.name
       or position('/'||o.bucket_id||'/'||o.name in (s.value #>> '{}'))>0
       or position('/'||o.bucket_id||'/'||replace(o.name,' ','%20') in (s.value #>> '{}'))>0)
 on conflict do nothing;
 insert into private.platform_reset_kept_media
 select distinct 'r2','',v.value from private.platform_reset_kept_rows k,
 lateral jsonb_each_text(k.row_data) v where v.key in ('video_object_key','poster_object_key') and coalesce(v.value,'')<>''
 on conflict do nothing;
end $$;
revoke all on function private.prepare_review_reset(uuid) from public,anon,authenticated;

create function public.platform_reset_protect_review(p_actor uuid,p_emails text[],p_church_ids text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare ids uuid[]; normalized text[]; church_ids text[]; state private.platform_reset_control%rowtype;
begin
 select * into state from private.platform_reset_control where singleton for update;
 if state.consumed_at is not null then raise exception 'The one-time reset has already been used.'; end if;
 if not exists(select 1 from public.developer_accounts d join auth.users u on u.id=p_actor
   where d.status='active' and d.developer_role='super_developer'
   and (d.user_id=p_actor or (d.user_id is null and lower(d.email)=lower(u.email)))) then
   raise exception 'Only the platform owner can configure review protection.' using errcode='42501';
 end if;
 select array_agg(distinct lower(trim(e))) into normalized from unnest(p_emails) e where trim(e)<>'';
 select array_agg(distinct trim(c)) into church_ids from unnest(p_church_ids) c where trim(c)<>'';
 if coalesce(cardinality(normalized),0) not between 1 and 20 or coalesce(cardinality(church_ids),0) not between 1 and 10 then
   raise exception 'Enter the existing Google Play review login emails and church IDs.';
 end if;
 select array_agg(id) into ids from auth.users where lower(email)=any(normalized);
 if coalesce(cardinality(ids),0)<>cardinality(normalized) then raise exception 'Every review email must match an existing account.'; end if;
 if exists(select 1 from unnest(ids) i where not exists(select 1 from public.users u where u.id=i and u."placeId"=any(church_ids))) then
   raise exception 'Each review account must belong to one of the selected churches.';
 end if;
 insert into private.platform_reset_review_protection(singleton,user_ids,church_ids,configured_by)
 values(true,ids,church_ids,p_actor) on conflict(singleton) do update set
 user_ids=excluded.user_ids,church_ids=excluded.church_ids,configured_by=p_actor,configured_at=now();
 perform private.prepare_review_reset(p_actor);
 return jsonb_build_object('saved',true);
end $$;
revoke all on function public.platform_reset_protect_review(uuid,text[],text[]) from public,anon,authenticated;
grant execute on function public.platform_reset_protect_review(uuid,text[],text[]) to service_role;

-- The old destructive entry points become private and cannot be invoked via RPC.
alter function public.platform_reset_begin(uuid) set schema private;
alter function private.platform_reset_begin(uuid) rename to platform_reset_begin_legacy;
revoke all on function private.platform_reset_begin_legacy(uuid) from public,anon,authenticated,service_role;
create function public.platform_reset_begin(p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=private.platform_reset_begin_legacy(p_actor);
 -- Runs in the same transaction after freezing writers. Failure rolls the
 -- entire begin back, including the one-time consumed marker.
 perform private.prepare_review_reset(p_actor);
 return result;
end $$;
revoke all on function public.platform_reset_begin(uuid) from public,anon,authenticated;
grant execute on function public.platform_reset_begin(uuid) to service_role;

alter function public.platform_reset_worker(text,uuid,text) set schema private;
alter function private.platform_reset_worker(text,uuid,text) rename to platform_reset_worker_legacy;
revoke all on function private.platform_reset_worker_legacy(text,uuid,text) from public,anon,authenticated,service_role;
create function public.platform_reset_worker(p_command text,p_lease uuid default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare state private.platform_reset_control%rowtype; t record; remaining bigint; removed bigint; progress bigint; result jsonb; attempts integer:=0;
begin
 select * into state from private.platform_reset_control where singleton for update;
 if state.phase in ('idle','complete') then return null; end if;
 if p_command='claim' then
   result:=private.platform_reset_worker_legacy(p_command,p_lease,p_error);
   if result is null then return null; end if;
   return result||jsonb_build_object('r2_after',state.r2_after);
 end if;
 if p_lease is null or p_lease is distinct from state.lease_id or state.lease_until<=now() then raise exception 'The cleanup lease expired.' using errcode='42501'; end if;
 if p_command='purge' and state.phase='data' then
   if not exists(select 1 from private.platform_reset_kept_rows where table_name='auth.users' and row_key->>'id'=state.keeper_id::text)
     or not exists(select 1 from private.platform_reset_review_protection) then raise exception 'Review preservation check failed.'; end if;
   perform set_config('grace.reset_worker','on',true);
   -- Row deletion preserves the actual credentials, IDs, church permissions and
   -- generated columns. FK constraints and triggers remain enabled throughout.
   loop
     progress:=0; remaining:=0; attempts:=attempts+1;
     for t in select table_name from private.platform_reset_tables where not preserve loop
       begin
         execute format('delete from public.%I r where not exists(select 1 from private.platform_reset_kept_rows k where k.table_name=%L and to_jsonb(r) @> k.row_key)',t.table_name,t.table_name);
         get diagnostics removed=row_count; progress:=progress+removed;
       exception when foreign_key_violation then remaining:=remaining+1;
       end;
     end loop;
     for t in select table_name from private.platform_reset_tables where not preserve loop
       execute format('select count(*) from public.%I r where not exists(select 1 from private.platform_reset_kept_rows k where k.table_name=%L and to_jsonb(r) @> k.row_key)',t.table_name,t.table_name) into removed;
       remaining:=remaining+removed;
     end loop;
     exit when remaining=0;
     if progress=0 or attempts>100 then raise exception 'Unreviewed dependencies prevent a safe reset.'; end if;
   end loop;
   -- Clear orphaned preparation leases without deleting retained review quizzes.
   if to_regclass('private.daily_content_batch_jobs') is not null then execute 'truncate private.daily_content_batch_jobs,private.quiz_generation_leases'; end if;
   update public.users set "placeId"=null,"placeName"=null,roles=array['Member'],"defaultRole"='Member'
    where not exists(select 1 from private.platform_reset_review_protection c where public.users."placeId"=any(c.church_ids));
   update private.platform_reset_control set phase='storage',last_error=null,updated_at=now() where singleton;
   perform set_config('grace.reset_worker','off',true);
 elsif p_command='storage_batch' and state.phase='storage' then
   return (select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket_id,'path',name)),'[]'::jsonb)
     from (select bucket_id,name from storage.objects o where not exists(select 1 from private.platform_reset_kept_media k
       where k.provider='storage' and k.bucket=o.bucket_id and k.path=o.name) order by bucket_id,name limit 100) s);
 elsif p_command='account_batch' and state.phase='accounts' then
   return (select coalesce(jsonb_agg(id),'[]'::jsonb) from (select id from auth.users a where not exists(
     select 1 from private.platform_reset_kept_rows k where k.table_name='auth.users' and k.row_key->>'id'=a.id::text) order by id limit 50) u);
 elsif p_command='r2_cursor' and state.phase='r2' then
   update private.platform_reset_control set r2_after=nullif(p_error,''),updated_at=now() where singleton;
 elsif p_command='advance' and state.phase='storage' then
   if exists(select 1 from storage.objects o where not exists(select 1 from private.platform_reset_kept_media k
     where k.provider='storage' and k.bucket=o.bucket_id and k.path=o.name)) then raise exception 'Storage cleanup is not finished.'; end if;
   update private.platform_reset_control set phase='r2',r2_after=null,updated_at=now() where singleton;
 elsif p_command='advance' and state.phase='r2' then
   update private.platform_reset_control set r2_after=null where singleton;
   return private.platform_reset_worker_legacy(p_command,p_lease,p_error);
 elsif p_command='advance' and state.phase='accounts' then
   if exists(select 1 from auth.users a where not exists(select 1 from private.platform_reset_kept_rows k
     where k.table_name='auth.users' and k.row_key->>'id'=a.id::text)) then raise exception 'Account cleanup is not finished.'; end if;
   if exists(select 1 from private.platform_reset_kept_rows k where k.table_name='auth.users' and not exists(
      select 1 from auth.users a where a.id::text=k.row_key->>'id')) then raise exception 'Protected account verification failed.'; end if;
   for t in select table_name from private.platform_reset_tables loop
     execute format('select count(*) from private.platform_reset_kept_rows k where k.table_name=%L and not exists(select 1 from public.%I r where to_jsonb(r) @> k.row_key)',t.table_name,t.table_name) into remaining;
     if remaining>0 then raise exception 'Protected review record verification failed.'; end if;
   end loop;
   if exists(select 1 from private.platform_reset_kept_media k where k.provider='storage' and not exists(
     select 1 from storage.objects o where o.bucket_id=k.bucket and o.name=k.path)) then raise exception 'Protected review media verification failed.'; end if;
   update private.platform_reset_control set phase='complete',completed_at=now(),updated_at=now(),last_error=null where singleton;
 else return private.platform_reset_worker_legacy(p_command,p_lease,p_error);
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.platform_reset_worker(text,uuid,text) from public,anon,authenticated;
grant execute on function public.platform_reset_worker(text,uuid,text) to service_role;

create function public.platform_reset_filter_r2_keys(p_keys text[],p_lease uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if coalesce(cardinality(p_keys),0)>50 or not exists(select 1 from private.platform_reset_control where phase='r2' and lease_id=p_lease and lease_until>now()) then
   raise exception 'The cleanup lease expired.' using errcode='42501'; end if;
 return (select coalesce(jsonb_agg(k),'[]'::jsonb) from unnest(p_keys) k where not exists(
   select 1 from private.platform_reset_kept_media m where m.provider='r2' and m.path=k));
end $$;
revoke all on function public.platform_reset_filter_r2_keys(text[],uuid) from public,anon,authenticated;
grant execute on function public.platform_reset_filter_r2_keys(text[],uuid) to service_role;

alter function public.platform_operations_status(uuid) set schema private;
alter function private.platform_operations_status(uuid) rename to platform_operations_status_legacy;
revoke all on function private.platform_operations_status_legacy(uuid) from public,anon,authenticated,service_role;
create function public.platform_operations_status(p_actor uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; configured boolean; protection jsonb;
begin
 result:=private.platform_operations_status_legacy(p_actor);
 select exists(select 1 from private.platform_reset_review_protection) into configured;
 protection:=jsonb_build_object('configured',configured,
  'review_emails',(select coalesce(jsonb_agg(a.email order by a.email),'[]') from auth.users a where a.id in (select unnest(user_ids) from private.platform_reset_review_protection)),
  'churches',(select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name)),'[]') from public.churches c where c.id::text in (select unnest(church_ids) from private.platform_reset_review_protection)),
  'kept_accounts',(select count(*) from private.platform_reset_kept_rows where table_name='auth.users'),
  'kept_rows',(select count(*) from private.platform_reset_kept_rows where table_name<>'auth.users'),
  'kept_media',(select count(*) from private.platform_reset_kept_media));
 return jsonb_set(result,'{reset}',(result->'reset')||jsonb_build_object('review_protection',protection,
   'can_start',(result#>>'{reset,can_start}')::boolean and configured));
end $$;
revoke all on function public.platform_operations_status(uuid) from public,anon,authenticated;
grant execute on function public.platform_operations_status(uuid) to service_role;
