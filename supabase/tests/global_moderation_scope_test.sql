begin;
create temporary table mod_assertions(description text);
create function pg_temp.check_mod(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Moderation test failed: %', description; end if;
  insert into mod_assertions values(description);
end;
$$;
do $test$
declare
  loner uuid := gen_random_uuid();   -- no church at all
  creator uuid := gen_random_uuid();
  reel_id uuid;
  inserted integer;
  visible boolean;
  denied boolean := false;
begin
  insert into auth.users(id,email,aud,role)
  select u, u::text||'@audit.invalid','authenticated','authenticated'
  from unnest(array[loner,creator]) u;

  insert into public.reels(author_id,caption,visibility,status,published_at,video_object_key)
    values(creator::text,'Global reel','public','ready',now(),'reels/'||creator::text||'/g/video.mp4')
    returning id into reel_id;

  -- Before: visible to a church-less viewer.
  perform pg_temp.check_mod(private.can_view_reel(loner,reel_id),
    'a church-less viewer can see a public reel');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',loner,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);

  -- Reporting with the global scope now succeeds where it was rejected.
  insert into public.content_reports(church_id,reporter_id,content_type,content_id,reported_user_id,reason)
    values(public.grace_connect_global_scope_id(),loner::text,'reel',reel_id::text,creator::text,'inappropriate');
  get diagnostics inserted = row_count;
  perform set_config('role','postgres',true);
  perform pg_temp.check_mod(inserted=1,'a church-less viewer can report a reel');

  -- Blocking likewise.
  perform set_config('role','authenticated',true);
  insert into public.user_blocks(church_id,blocker_id,blocked_user_id)
    values(public.grace_connect_global_scope_id(),loner::text,creator::text);
  get diagnostics inserted = row_count;
  perform set_config('role','postgres',true);
  perform pg_temp.check_mod(inserted=1,'a church-less viewer can block a creator');

  -- And the block actually takes effect on the feed.
  visible := private.can_view_reel(loner,reel_id);
  perform pg_temp.check_mod(not visible,
    'a global block immediately hides that creator''s reels');

  -- A report cannot be filed in someone else's name.
  perform set_config('role','authenticated',true);
  begin
    insert into public.content_reports(church_id,reporter_id,content_type,content_id,reason)
      values(public.grace_connect_global_scope_id(),creator::text,'reel',reel_id::text,'spam');
  exception when others then denied := true; end;
  perform set_config('role','postgres',true);
  perform pg_temp.check_mod(denied,'a report cannot be filed under another member''s id');
end;
$test$;
select count(*) as assertions_passed from mod_assertions;
rollback;
