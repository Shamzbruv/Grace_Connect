begin;

select set_config('test.author',(select id::text from auth.users order by created_at limit 1),true);
insert into public.community_posts(id,author_id,author_name,content,scope,place_id)
values
('00000000-0000-4000-8000-000000000071',current_setting('test.author')::uuid,'Test','Rollback private','church','rollback-only-unrelated-church'),
('00000000-0000-4000-8000-000000000072',current_setting('test.author')::uuid,'Test','Rollback public','global',null);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000092","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
if exists(select 1 from public.community_posts where id='00000000-0000-4000-8000-000000000071') then
 raise exception 'Unrelated viewer can read private post'; end if;
if not exists(select 1 from public.community_posts where id='00000000-0000-4000-8000-000000000072') then
 raise exception 'Public post missing'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('test.author'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
if not exists(select 1 from public.community_posts where id='00000000-0000-4000-8000-000000000071') then
 raise exception 'Author cannot read own post'; end if;
end $$;
reset role;
select 'Shared post permissions passed; all fixtures rolled back' as result;

rollback;
