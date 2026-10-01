begin;
select set_config('request.jwt.claims',jsonb_build_object('sub',
  (select user_id from public.developer_accounts where developer_role='super_developer'
   and status='active' and user_id is not null limit 1),'role','authenticated')::text,true);
set local role authenticated;
insert into public.quote_backgrounds(id,file_name,title)
values('00000000-0000-4000-8000-000000000061','rollback-only.png','Rollback test');
update public.quote_backgrounds set is_active=false where id='00000000-0000-4000-8000-000000000061';
reset role;
do $$ begin
 if public.quote_background_removal_pending('quote_backgrounds/rollback-only.png') then
   raise exception 'Active catalogue image was eligible for deletion'; end if;
end $$;
set local role authenticated;
delete from public.quote_backgrounds where id='00000000-0000-4000-8000-000000000061';
reset role;
do $$ begin
 if not public.quote_background_removal_pending('quote_backgrounds/rollback-only.png') then
   raise exception 'Removed background was not queued'; end if;
 if (select count(*) from public.developer_audit_logs where target_id='00000000-0000-4000-8000-000000000061')<>3 then
   raise exception 'Background edits were not audited'; end if;
end $$;
select 'Catalogue insert/update/delete, audit and removal-only cleanup passed (rolled back)' as result;
rollback;
