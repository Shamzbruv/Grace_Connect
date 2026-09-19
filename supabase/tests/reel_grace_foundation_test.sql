begin;
create temporary table reel_assertions(description text);
create function pg_temp.check_reel(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Reel test failed: %', description; end if;
  insert into reel_assertions values(description);
end;
$$;
do $test$
declare
  author uuid := gen_random_uuid();
  follower uuid := gen_random_uuid();
  stranger uuid := gen_random_uuid();
  churchmate uuid := gen_random_uuid();
  blocked uuid := gen_random_uuid();
  c text := 'reel_church_'||gen_random_uuid()::text;
  public_reel uuid; followers_reel uuid; church_reel uuid; draft_reel uuid;
  feed jsonb; denied boolean;
begin
  insert into auth.users(id,email,aud,role)
  select u, u::text||'@audit.invalid','authenticated','authenticated'
  from unnest(array[author,follower,stranger,churchmate,blocked]) u;

  insert into public.churches(id,name,church_status,timezone,public_visibility)
    values(c,'Reel audit church','approved','America/Jamaica',true);
  insert into public.church_memberships(user_id,church_id,membership_status,reviewed_at)
    values(author,c,'active',now()),(churchmate,c,'active',now());

  insert into public.social_follows(follower_id,following_id,status)
    values(follower::text,author::text,'accepted');
  insert into public.user_blocks(church_id,blocker_id,blocked_user_id)
    values(c,blocked::text,author::text);

  insert into public.reels(author_id,author_church_id,caption,visibility,status,published_at,ranking_score,video_object_key)
    values(author::text,c,'Public reel','public','ready',now(),10,'reels/'||author::text||'/pub/video.mp4')
    returning id into public_reel;
  insert into public.reels(author_id,author_church_id,caption,visibility,status,published_at,ranking_score,video_object_key)
    values(author::text,c,'Followers reel','followers','ready',now(),9,'reels/'||author::text||'/fol/video.mp4')
    returning id into followers_reel;
  insert into public.reels(author_id,author_church_id,caption,visibility,status,published_at,ranking_score,video_object_key)
    values(author::text,c,'Church reel','church','ready',now(),8,'reels/'||author::text||'/chu/video.mp4')
    returning id into church_reel;
  insert into public.reels(author_id,author_church_id,caption,visibility,status,ranking_score,video_object_key)
    values(author::text,c,'Still uploading','public','uploading',7,'reels/'||author::text||'/drf/video.mp4')
    returning id into draft_reel;

  -- Visibility predicate, the single rule both the feed and signing use.
  perform pg_temp.check_reel(private.can_view_reel(stranger,public_reel),'stranger sees a public reel');
  perform pg_temp.check_reel(not private.can_view_reel(stranger,followers_reel),'stranger cannot see a followers-only reel');
  perform pg_temp.check_reel(private.can_view_reel(follower,followers_reel),'accepted follower sees a followers-only reel');
  perform pg_temp.check_reel(not private.can_view_reel(stranger,church_reel),'outsider cannot see a church-only reel');
  perform pg_temp.check_reel(private.can_view_reel(churchmate,church_reel),'church member sees a church-only reel');
  perform pg_temp.check_reel(not private.can_view_reel(stranger,draft_reel),'an unfinished reel is not visible');
  perform pg_temp.check_reel(private.can_view_reel(author,draft_reel),'the author sees their own unfinished reel');
  perform pg_temp.check_reel(not private.can_view_reel(blocked,public_reel),'a block hides even a public reel');

  -- Feed RPC honours the same rules and never returns a URL.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
  feed := public.get_reel_grace_feed('discover',null,12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=1,'discover returns only the permitted reel');
  perform pg_temp.check_reel(feed->'reels'->0->>'id'=public_reel::text,'discover returns the public reel');
  perform pg_temp.check_reel(feed->'reels'->0 ? 'video_object_key','feed returns an object key');
  perform pg_temp.check_reel(not (feed->'reels'->0 ? 'video_url'),'feed never returns a playback URL');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',churchmate,'role','authenticated')::text,true);
  feed := public.get_reel_grace_feed('discover',null,12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=2,'church member sees public and church reels');

  -- Following mode is restricted to accepted follows.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',follower,'role','authenticated')::text,true);
  feed := public.get_reel_grace_feed('following',null,12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=2,'following returns the followed author''s permitted reels');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
  feed := public.get_reel_grace_feed('following',null,12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=0,'following is empty without an accepted follow');

  -- Not interested removes a reel from later pages.
  insert into public.reel_user_feedback(user_id,reel_id,feedback_type)
    values(stranger::text,public_reel,'not_interested');
  feed := public.get_reel_grace_feed('discover',null,12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=0,'not interested removes the reel from discover');

  -- Paging: a full page returns a cursor, a short page does not.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',churchmate,'role','authenticated')::text,true);
  feed := public.get_reel_grace_feed('discover',null,1);
  perform pg_temp.check_reel(feed->'next_cursor' is not null and feed->>'next_cursor' <> 'null','a full page returns a cursor');
  feed := public.get_reel_grace_feed('discover',feed->'next_cursor',12);
  perform pg_temp.check_reel(jsonb_array_length(feed->'reels')=1,'the cursor advances past the first reel');
  perform pg_temp.check_reel(feed->'reels'->0->>'id'=church_reel::text,'the second page starts at the next lowest score');

  denied := false;
  begin perform public.get_reel_grace_feed('nonsense',null,12);
    exception when others then denied := true; end;
  perform pg_temp.check_reel(denied,'an unknown feed mode is rejected');

  -- Grants
  perform pg_temp.check_reel(not has_function_privilege('anon','public.get_reel_grace_feed(text,jsonb,integer)','EXECUTE'),'anon cannot run the feed');
  perform pg_temp.check_reel(has_function_privilege('authenticated','public.get_reel_grace_feed(text,jsonb,integer)','EXECUTE'),'authenticated can run the feed');
  perform pg_temp.check_reel(not has_table_privilege('anon','public.reels','SELECT'),'anon cannot select reels');
  perform pg_temp.check_reel(not has_table_privilege('anon','public.reel_upload_sessions','SELECT'),'anon cannot select upload sessions');
  perform pg_temp.check_reel(not has_table_privilege('authenticated','public.reel_upload_sessions','INSERT'),'clients cannot mint upload sessions');
  perform pg_temp.check_reel(not has_function_privilege('authenticated','private.can_view_reel(uuid,uuid)','EXECUTE'),'the visibility predicate is not client callable');
end;
$test$;
select count(*) as assertions_passed from reel_assertions;
rollback;
