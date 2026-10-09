-- A shared quiz runs from its existing 07:00 release until 06:00 the next day.
create or replace function private.set_daily_quiz_play_window()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
 new.expires_at := (new.quiz_date::timestamp + interval '1 day 6 hours') at time zone 'America/Jamaica';
 if new.available_at >= new.expires_at then raise exception 'Quiz must open before its closing time'; end if;
 return new;
end;$$;
revoke all on function private.set_daily_quiz_play_window() from public,anon,authenticated;
create trigger daily_quiz_play_window before insert or update of quiz_date,available_at,expires_at
on public.daily_bible_quizzes for each row execute function private.set_daily_quiz_play_window();
update public.daily_bible_quizzes set expires_at=(quiz_date::timestamp + interval '1 day 6 hours') at time zone 'America/Jamaica'
where quiz_date >= (now() at time zone 'America/Jamaica')::date - 1 and status in ('published','scheduled');
create index if not exists daily_bible_quizzes_date_id_idx on public.daily_bible_quizzes(quiz_date,id);

-- Keep overnight/month-end scores with the original question set. Preserve all
-- existing blocking, profile visibility, authenticated access and church scoping.
CREATE OR REPLACE FUNCTION public.list_quiz_ranking(p_scope text DEFAULT 'church'::text, p_quiz_month text DEFAULT NULL::text, result_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor uuid := auth.uid();
  scope text := lower(coalesce(nullif(trim(p_scope), ''), 'church'));
  church text;
  capped integer := greatest(1, least(coalesce(result_limit, 25), 100));
  month_start date;
  calendar_zone text;
  month_end timestamptz;
  entries jsonb;
  viewer jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if scope not in ('church','global') then
    raise exception 'Unknown ranking scope.' using errcode = '22023';
  end if;
  church := public.grace_connect_leaderboard_church_id();
  calendar_zone := 'America/Jamaica';
  if nullif(btrim(p_quiz_month),'') is not null and
     p_quiz_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])(-01)?$' then
    raise exception 'Use a valid YYYY-MM month.' using errcode='22023';
  end if;
  month_start := case when nullif(btrim(p_quiz_month),'') is null
    then date_trunc('month',(now() at time zone calendar_zone) - interval '6 hours')::date
    else (left(p_quiz_month,7)||'-01')::date end;
  month_end := (month_start + interval '1 month 6 hours') at time zone calendar_zone;
  if scope = 'church' and coalesce(trim(church), '') = '' then
    return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
      'entries', '[]'::jsonb, 'viewer', null);
  end if;

  with scored as (
    select
      a.member_id,
      sum(coalesce(a.total_score, 0))::integer as total_score,
      sum(coalesce(a.correct_answers, 0))::integer as correct_answers,
      count(*) filter (where coalesce(a.total_score, 0) = 100)::integer
        as perfect_quizzes,
      count(*)::integer as quizzes_completed,
      sum(coalesce(a.total_response_time_ms, 0))::bigint as response_ms
    from public.quiz_attempts a
    join public.daily_bible_quizzes q on q.id = a.quiz_id
    where a.status = 'completed'
      and not exists(select 1 from public.user_blocks b where
        (b.blocker_id=actor::text and b.blocked_user_id=a.member_id::text) or
        (b.blocked_user_id=actor::text and b.blocker_id=a.member_id::text))
      and q.quiz_date >= month_start
      and q.quiz_date < (month_start + interval '1 month')::date
      and (scope = 'global' or coalesce(a.church_id_at_attempt, a.church_id) = church)
    group by a.member_id
  ), named as (
    select
      s.*,
      -- Matched on both keys: this table stores the auth id in `id` for some
      -- rows and as text in `uid` for others, and joining on one alone left
      -- half the board showing the 'Member' placeholder.
      (
        select coalesce(nullif(btrim(u."displayName"), ''),
                        nullif(btrim(u."fullName"), ''))
        from public.users u
        where u.uid = s.member_id::text or u.id = s.member_id
        limit 1
      ) as full_name,
      (
        select u."photoUrl"
        from public.users u
        where u.uid = s.member_id::text or u.id = s.member_id
        limit 1
      ) as photo_url
    from scored s
  ), ranked as (
    select
      n.member_id::text as user_id,
      case
        when scope = 'global' and n.member_id <> actor
          then private.display_first_name(n.full_name)
        else coalesce(n.full_name, 'Member')
      end as user_name,
      n.photo_url,
      n.total_score, n.correct_answers, n.perfect_quizzes, n.quizzes_completed,
      rank() over (
        order by n.total_score desc, n.perfect_quizzes desc, n.correct_answers desc, n.response_ms asc
      ) as position
    from named n
  ), page as (
    select * from ranked order by position, user_id limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position,
        'user_id', case when private.ranking_identity_visible(p.user_id,scope) then p.user_id end,
        'user_name', case when private.ranking_identity_visible(p.user_id,scope) then p.user_name else 'Private member' end,
        'photo_url', case when private.ranking_identity_visible(p.user_id,scope) then p.photo_url end, 'total_score', p.total_score,
        'correct_answers', p.correct_answers,
        'perfect_quizzes', p.perfect_quizzes,
        'quizzes_completed', p.quizzes_completed,
        'is_viewer', p.user_id = actor::text
      ) order by p.position, p.user_id) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'total_score', r.total_score,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
    'entries', entries, 'viewer', viewer, 'calendar_zone', calendar_zone,
    'next_month_at', month_end);
end;
$function$
;
revoke all on function public.list_quiz_ranking(text,text,integer) from public,anon;
grant execute on function public.list_quiz_ranking(text,text,integer) to authenticated;

-- Awards cannot finalize while the final day's quiz is still open. Do not
-- rewrite previous awards or invoke the notification worker during migration.
do $$declare job bigint;begin
 select jobid into job from cron.job where jobname='daily-bible-quiz-monthly-winners';
 if job is not null then perform cron.alter_job(job, schedule := '5 11 1 * *');end if;
end;$$;
