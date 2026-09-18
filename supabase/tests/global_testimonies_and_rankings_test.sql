begin;
create temporary table launch_global_assertions(description text);
create function pg_temp.check_global(ok boolean, description text)
returns void language plpgsql as $$
begin
  if ok is distinct from true then raise exception 'Global test failed: %', description; end if;
  insert into launch_global_assertions values(description);
end;
$$;
do $test$
declare
  member uuid := gen_random_uuid();
  outsider uuid := gen_random_uuid();
  c text := 'launch_global_'||gen_random_uuid()::text;
  visible integer;
  ranking jsonb;
  denied boolean;
begin
  insert into auth.users(id,email,aud,role) values
    (member, member::text||'@audit.invalid','authenticated','authenticated'),
    (outsider, outsider::text||'@audit.invalid','authenticated','authenticated');
  -- current_active_church_id() only resolves approved, publicly visible
  -- churches, so the fixture must satisfy both to exercise the church scope.
  insert into public.churches(id,name,church_status,timezone,public_visibility)
    values(c,'Rollback global audit','approved','America/Jamaica',true);
  insert into public.church_memberships(user_id,church_id,membership_status,reviewed_at)
    values(member,c,'active',now());
  -- auth.users insert already creates the profile row via trigger.
  update public.users set "fullName"='Member One' where id = member;
  update public.users set "fullName"='Outsider Two' where id = outsider;

  -- A church testimony and a global one.
  insert into public.testimonies(church_id,author_id,author_name,content,scope)
    values(c,member::text,'Member One','Church only testimony','church');
  insert into public.testimonies(church_id,author_id,author_name,content,scope)
    values(null,outsider::text,'Outsider Two','Global testimony','global');

  -- Historical church rows can never be global: the constraint forbids it.
  denied := false;
  begin
    update public.testimonies set scope='global' where church_id = c;
  exception when check_violation then denied := true; end;
  perform pg_temp.check_global(denied,'church testimony cannot be flipped to global while keeping its church');

  -- Someone with no church sees the global testimony only. Counts are taken
  -- under the authenticated role, then asserted after the role is restored,
  -- because the temp assertion table is not writable as authenticated.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  select count(*) into visible from public.testimonies where content in ('Church only testimony','Global testimony');
  perform set_config('role','postgres',true);
  perform pg_temp.check_global(visible=1,'church-less viewer sees global testimony only');

  -- A church member sees both their church feed and the global feed.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',member,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  select count(*) into visible from public.testimonies where content in ('Church only testimony','Global testimony');
  perform set_config('role','postgres',true);
  perform pg_temp.check_global(visible=2,'church member sees church and global testimonies');

  -- Rankings: the viewer's own position is reported even off the page.
  insert into public.bible_streaks(user_id,church_id,user_name,streak_count,last_read_date,updated_at)
    values(member,c,'Member One',9,(now() at time zone 'UTC')::date,now()),
          (outsider,'other_church','Outsider Two',40,(now() at time zone 'UTC')::date,now());
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',member,'role','authenticated')::text,true);
  ranking := public.list_bible_streak_ranking('global',1);
  perform pg_temp.check_global(jsonb_array_length(ranking->'entries')=1,'global streak page respects the limit');
  perform pg_temp.check_global((ranking->'entries'->0->>'user_id')=outsider::text,'global streak ranks the highest streak first');
  perform pg_temp.check_global((ranking->'viewer'->>'rank')::int=2,'viewer rank reported even when off the page');
  ranking := public.list_bible_streak_ranking('church',25);
  perform pg_temp.check_global(jsonb_array_length(ranking->'entries')=1,'church streak scope excludes other churches');
  perform pg_temp.check_global((ranking->'entries'->0->>'is_viewer')::boolean,'church streak marks the viewer');

  ranking := public.list_quiz_ranking('global',to_char(now(),'YYYY-MM'),25);
  perform pg_temp.check_global(ranking ? 'entries','quiz ranking returns an envelope');
  perform pg_temp.check_global((ranking->>'scope')='global','quiz ranking echoes its scope');

  denied := false;
  begin perform public.list_bible_streak_ranking('nonsense',10);
    exception when others then denied := true; end;
  perform pg_temp.check_global(denied,'unknown ranking scope rejected');

  perform pg_temp.check_global(not has_function_privilege('anon',
    'public.list_bible_streak_ranking(text,integer)','EXECUTE'),'anonymous streak ranking denied');
  perform pg_temp.check_global(not has_function_privilege('anon',
    'public.list_quiz_ranking(text,text,integer)','EXECUTE'),'anonymous quiz ranking denied');
  perform pg_temp.check_global(has_function_privilege('authenticated',
    'public.list_quiz_ranking(text,text,integer)','EXECUTE'),'authenticated quiz ranking granted');
end;
$test$;
select count(*) as assertions_passed from launch_global_assertions;
rollback;
