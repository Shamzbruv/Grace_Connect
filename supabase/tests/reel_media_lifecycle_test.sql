begin;
create temporary table reel_life_assertions(description text);
create function pg_temp.check_life(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Lifecycle test failed: %', description; end if;
  insert into reel_life_assertions values(description);
end;
$$;
do $test$
declare
  author uuid := gen_random_uuid();
  other uuid := gen_random_uuid();
  reel uuid;
  result jsonb;
  denied boolean;
  session_id uuid;
begin
  insert into auth.users(id,email,aud,role)
  select u, u::text||'@audit.invalid','authenticated','authenticated'
  from unnest(array[author,other]) u;

  insert into public.reels(author_id,caption,visibility,status,published_at,video_object_key,poster_object_key)
    values(author::text,'Lifecycle','public','ready',now(),
           'reels/'||author::text||'/v/video.mp4','reels/'||author::text||'/v/poster.webp')
    returning id into reel;

  -- Another member cannot delete it.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other,'role','authenticated')::text,true);
  denied := false;
  begin perform public.delete_my_reel(reel); exception when others then denied := true; end;
  perform pg_temp.check_life(denied,'a non-author cannot delete a reel');
  perform pg_temp.check_life(
    (select deleted_at is null from public.reels where id=reel),
    'a refused delete leaves the reel intact');

  -- The author can, and both object keys are surrendered for removal.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',author,'role','authenticated')::text,true);
  result := public.delete_my_reel(reel);
  perform pg_temp.check_life((result->>'deleted')::boolean,'the author can delete their reel');
  perform pg_temp.check_life(jsonb_array_length(result->'object_keys')=2,
    'deletion surrenders both the video and the poster');
  perform pg_temp.check_life(
    (select count(*) from public.reel_media_cleanup_jobs
      where object_key like 'reels/'||author::text||'/v/%' and completed_at is null)=2,
    'both objects are queued for removal so failed deletes are retried');
  perform pg_temp.check_life(
    (select deleted_at is not null and status='deleted' from public.reels where id=reel),
    'the reel is hidden immediately, before the bytes are gone');

  -- Idempotent: a retry after a dropped response must not error.
  result := public.delete_my_reel(reel);
  perform pg_temp.check_life((result->>'already_deleted')::boolean,'re-deleting reports already deleted');
  perform pg_temp.check_life((result->>'deleted')::boolean,'re-deleting still succeeds');
  result := public.delete_my_reel(gen_random_uuid());
  perform pg_temp.check_life((result->>'deleted')::boolean,'deleting an unknown reel succeeds rather than erroring');
  perform pg_temp.check_life(
    (select count(*) from public.reel_media_cleanup_jobs
      where object_key like 'reels/'||author::text||'/v/%' and completed_at is null)=2,
    'a repeated delete does not duplicate cleanup work');

  -- An abandoned upload surrenders its objects and takes its draft reel away.
  insert into public.reels(id,author_id,status,video_object_key,poster_object_key)
    values(gen_random_uuid(),author::text,'uploading',
      'reels/'||author::text||'/orphan/video.mp4','reels/'||author::text||'/orphan/poster.webp')
    returning id into reel;
  insert into public.reel_upload_sessions(reel_id,user_id,video_object_key,poster_object_key,status,expires_at)
    values(reel,author::text,'reels/'||author::text||'/orphan/video.mp4',
           'reels/'||author::text||'/orphan/poster.webp','pending',now()-interval '1 hour')
    returning id into session_id;

  perform public.expire_reel_upload_sessions();
  perform pg_temp.check_life(
    (select count(*) from public.reel_media_cleanup_jobs
      where object_key like 'reels/'||author::text||'/orphan/%' and completed_at is null)=2,
    'an abandoned upload surrenders both objects for removal');
  perform pg_temp.check_life((select count(*) from public.reels where id=reel)=0,
    'an unpublished reel does not outlive its expired session');

  -- Claiming backs off rather than spinning on a failing object.
  perform pg_temp.check_life(
    (select count(*) from public.claim_reel_cleanup_jobs(10)) > 0,'cleanup work can be claimed');
  perform pg_temp.check_life(
    (select count(*) from public.claim_reel_cleanup_jobs(10)) = 0,
    'a just-claimed job is not immediately reclaimed');

  perform pg_temp.check_life(not has_function_privilege('authenticated',
    'public.expire_reel_upload_sessions()','EXECUTE'),'clients cannot run the orphan sweep');
  perform pg_temp.check_life(not has_function_privilege('authenticated',
    'public.claim_reel_cleanup_jobs(integer)','EXECUTE'),'clients cannot claim cleanup work');
  perform pg_temp.check_life(not has_table_privilege('authenticated',
    'public.reel_media_cleanup_jobs','SELECT'),'clients cannot read the cleanup queue');
end;
$test$;
select count(*) as assertions_passed from reel_life_assertions;
rollback;
