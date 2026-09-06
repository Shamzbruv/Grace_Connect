-- Run as the project database administrator after the retention migration.
-- All fixtures, content cleanup, queue changes and presence changes roll back.
begin;
set local statement_timeout='20s';
do $$
declare
  author uuid := (select id from auth.users limit 1);
  old_post uuid := gen_random_uuid();
  recent_post uuid := gen_random_uuid();
  future_post uuid := gen_random_uuid();
  test_path text := '__retention_test__/' || gen_random_uuid()::text || '.jpg';
  item public.community_posts;
begin
  if author is null then raise exception 'Test requires an existing auth user'; end if;
  insert into public.community_posts(id,author_id,author_name,content,created_at,expires_at,is_persistent,post_type,media_path)
  values(old_post,author,'Retention test','Rollback fixture',now()-interval '31 days',null,true,'social_post',test_path),
        (recent_post,author,'Retention test','Rollback fixture',now()-interval '29 days',null,true,'social_post',test_path),
        (future_post,author,'Retention test','Rollback fixture',now()+interval '1 day',null,true,'social_post',null);
  select * into item from public.community_posts where id=old_post;
  if item.expires_at is distinct from item.created_at+interval '30 days' or item.is_persistent then
    raise exception 'Legacy social posts bypassed 30-day retention';
  end if;
  update public.community_posts set created_at=now(),expires_at=now()+interval '90 days',is_persistent=true where id=old_post;
  select * into item from public.community_posts where id=old_post;
  if item.created_at<>now()-interval '31 days' or item.expires_at<>now()-interval '1 day' or item.is_persistent then
    raise exception 'An update extended the retention window';
  end if;
  if exists(select 1 from public.community_posts where id=future_post and created_at>now()) then
    raise exception 'Future timestamps bypassed retention';
  end if;
  perform public.cleanup_vanishing_content();
  if exists(select 1 from public.community_posts where id=old_post) then raise exception 'Expired post survived'; end if;
  if not exists(select 1 from public.community_posts where id=recent_post) then raise exception 'Recent post was removed'; end if;
  if not exists(select 1 from public.media_cleanup_queue where object_path=test_path and bucket_id='community_media') then
    raise exception 'Expired media was not queued';
  end if;
  if not public.retention_media_is_referenced(test_path) then raise exception 'Shared media lost its protection'; end if;
  if exists(select 1 from public.list_retention_media_candidates(100) where object_path=test_path) then
    raise exception 'Referenced file selected for deletion';
  end if;
  delete from public.community_posts where id=recent_post;
  if public.retention_media_is_referenced(test_path) then raise exception 'Unreferenced test file remained protected'; end if;
  if public.retention_media_path('../private',null,'community_media') is not null
     or public.retention_media_path(null,'https://other.example/image.jpg','community_media') is not null
     or public.retention_media_path('user/image.jpg',null,'avatars') is not null then
    raise exception 'Unsafe path accepted';
  end if;
  if public.retention_media_path(null,'https://nimgsgnkcvddomrgkawb.supabase.co/storage/v1/object/public/community_media/user/a%20b.jpg?x=1','community_media') is distinct from 'user/a b.jpg' then
    raise exception 'Legacy public URL was not parsed';
  end if;
  if has_table_privilege('authenticated','public.media_cleanup_queue','DELETE')
     or has_function_privilege('anon','public.list_retention_media_candidates(integer)','EXECUTE')
     or has_function_privilege('authenticated','public.retention_media_is_referenced(text)','EXECUTE') then
    raise exception 'Cleanup exposed to an app user';
  end if;
  perform public.refresh_grace_room_presence();
  if public.refresh_grace_room_presence()<>0 then raise exception 'Unchanged presence still rewrites rooms'; end if;
end;
$$;
rollback;
select 'Retention SQL assertions passed; all fixtures rolled back.' as result;
