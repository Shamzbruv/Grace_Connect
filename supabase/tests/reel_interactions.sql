begin;

insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000091','reel-rollback-only@example.test'),
('00000000-0000-4000-8000-000000000092','viewer-rollback-only@example.test');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000091","role":"authenticated"}', true);
insert into public.reels(id,author_id,caption,status,published_at)
values ('00000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000091','Rollback-only reel test','ready',now());
set local role authenticated;
insert into public.reel_likes(reel_id) values ('00000000-0000-4000-8000-000000000081');
insert into public.reel_comments(reel_id,body) values ('00000000-0000-4000-8000-000000000081','Rollback-only comment');
insert into public.social_saved_items(entity_type,entity_id) values ('reel','00000000-0000-4000-8000-000000000081');
do $$ declare d jsonb; begin
select public.get_reel_grace_detail('00000000-0000-4000-8000-000000000081') into d;
if d->>'like_count'<>'1' or d->>'comment_count'<>'1' or d->>'save_count'<>'1'
  or d->>'viewer_liked'<>'true' or d->>'viewer_saved'<>'true' then raise exception 'Wrong engagement: %',d; end if;
if jsonb_array_length(public.get_reel_grace_profile('00000000-0000-4000-8000-000000000091')->'reels')<>1
 then raise exception 'Profile missing reel'; end if;
begin
 insert into public.reel_likes(reel_id,user_id) values
 ('00000000-0000-4000-8000-000000000081','00000000-0000-4000-8000-000000000092');
 raise exception 'Forged user allowed';
exception when insufficient_privilege then null; end;
begin
 update public.reels set like_count=9000 where id='00000000-0000-4000-8000-000000000081';
 raise exception 'Counter forgery allowed';
exception when insufficient_privilege then null; end;
end $$;
delete from public.reel_likes where reel_id='00000000-0000-4000-8000-000000000081';
delete from public.reel_comments where reel_id='00000000-0000-4000-8000-000000000081';
delete from public.social_saved_items where entity_type='reel' and entity_id='00000000-0000-4000-8000-000000000081';
do $$ declare d jsonb; begin
select public.get_reel_grace_detail('00000000-0000-4000-8000-000000000081') into d;
if d->>'like_count'<>'0' or d->>'comment_count'<>'0' or d->>'save_count'<>'0'
then raise exception 'Counters not decremented: %',d; end if;
end $$;
reset role;
insert into public.reels(id,author_id,caption,status,visibility,published_at) values
('00000000-0000-4000-8000-000000000082','00000000-0000-4000-8000-000000000091','Private test','ready','followers',now());
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000092","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  if public.get_reel_grace_detail('00000000-0000-4000-8000-000000000082') is not null then raise exception 'Private reel leaked'; end if;
  if public.get_reel_grace_detail('00000000-0000-4000-8000-000000000081') is null then raise exception 'Public reel unavailable'; end if;
  begin
    insert into public.social_saved_items(entity_type,entity_id) values('reel','00000000-0000-4000-8000-000000000082');
    raise exception 'Private reel save allowed';
  exception when insufficient_privilege then null; end;
  insert into public.social_saved_items(entity_type,entity_id) values('reel','00000000-0000-4000-8000-000000000081');
  begin
    update public.social_saved_items set entity_type='post' where entity_id='00000000-0000-4000-8000-000000000081';
    raise exception 'Saved identity mutation allowed';
  exception when check_violation then null; end;
end $$;
reset role;
insert into public.user_blocks(church_id,blocker_id,blocked_user_id) values('grace_connect_global','00000000-0000-4000-8000-000000000091','00000000-0000-4000-8000-000000000092');
set local role authenticated;
do $$ begin
  if public.get_reel_grace_detail('00000000-0000-4000-8000-000000000081') is not null then raise exception 'Blocked reel leaked'; end if;
  if jsonb_array_length(public.get_reel_grace_profile('00000000-0000-4000-8000-000000000091')->'reels')<>0 then raise exception 'Blocked profile leaked'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
  begin
    perform public.get_reel_grace_detail('00000000-0000-4000-8000-000000000081');
    raise exception 'Anonymous detail access allowed';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'Reel authenticated writes, identity protection, counts, profile and deletes passed (rolled back)' as result;

rollback;
