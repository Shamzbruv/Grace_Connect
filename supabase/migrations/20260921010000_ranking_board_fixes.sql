-- Two ranking boards, two real defects.
--
-- 1. The Bible streak board went completely blank overnight. Entries were
--    filtered to last_read_date >= today - 1, so the moment the only active
--    streak aged past two days the global board reported "no streaks anywhere"
--    -- to every user, worldwide. The recency rule was there for a good
--    reason (a stale streak should not outrank an active one), but it was
--    applied as a filter when it only ever needed to be a sort key. Active
--    streaks still come first; inactive ones now appear below them instead of
--    emptying the board.
--
-- 2. The quiz board joined users on uid alone. This table keys some rows by
--    the uuid id and others by the text uid, so every member on the id side
--    missed the join and rendered as 'Member'. It also never returned
--    perfect_quizzes, which the panel displays.

create or replace function public.list_bible_streak_ranking(
  p_scope text default 'church',
  result_limit integer default 25
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  scope text := lower(coalesce(nullif(trim(p_scope), ''), 'church'));
  church text;
  capped integer := greatest(1, least(coalesce(result_limit, 25), 100));
  cutoff date;
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
  if scope = 'church' and coalesce(trim(church), '') = '' then
    return jsonb_build_object('scope', scope, 'entries', '[]'::jsonb, 'viewer', null);
  end if;

  -- Global uses UTC so no single region's calendar decides who counts as
  -- current; a church uses its own clock.
  cutoff := (
    case when scope = 'church'
      then (timezone(private.church_timezone(church), now()))::date
      else (now() at time zone 'UTC')::date
    end
  ) - 1;

  with ranked as (
    select
      bs.user_id::text as user_id,
      -- The viewer always sees their own full name so they can find
      -- themselves, even on a global board.
      case
        when scope = 'global' and bs.user_id <> actor
          then private.display_first_name(bs.user_name)
        else bs.user_name
      end as user_name,
      bs.photo_url,
      bs.streak_count,
      bs.last_read_date,
      (bs.last_read_date >= cutoff) as is_current,
      rank() over (
        order by
          (bs.last_read_date >= cutoff) desc,
          bs.streak_count desc,
          bs.last_read_date desc,
          bs.updated_at desc
      ) as position
    from public.bible_streaks bs
    where bs.streak_count > 0
      and (scope = 'global' or bs.church_id = church)
  ), page as (
    select * from ranked order by position limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position, 'user_id', p.user_id, 'user_name', p.user_name,
        'photo_url', p.photo_url, 'streak_count', p.streak_count,
        'last_read_date', p.last_read_date, 'is_current', p.is_current,
        'is_viewer', p.user_id = actor::text
      ) order by p.position) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'streak_count', r.streak_count,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'entries', entries, 'viewer', viewer);
end;
$$;
revoke all on function public.list_bible_streak_ranking(text, integer) from public, anon;
grant execute on function public.list_bible_streak_ranking(text, integer) to authenticated;

create or replace function public.list_quiz_ranking(
  p_scope text default 'church',
  p_quiz_month text default null,
  result_limit integer default 25
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  scope text := lower(coalesce(nullif(trim(p_scope), ''), 'church'));
  church text;
  capped integer := greatest(1, least(coalesce(result_limit, 25), 100));
  month_start date;
  entries jsonb;
  viewer jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if scope not in ('church','global') then
    raise exception 'Unknown ranking scope.' using errcode = '22023';
  end if;
  month_start := date_trunc('month',
    coalesce(to_date(nullif(trim(p_quiz_month), ''), 'YYYY-MM'), (now() at time zone 'UTC')::date)
  )::date;
  church := public.grace_connect_leaderboard_church_id();
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
    where a.status = 'completed'
      and a.completed_at >= month_start
      and a.completed_at < (month_start + interval '1 month')
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
        order by n.total_score desc, n.correct_answers desc, n.response_ms asc
      ) as position
    from named n
    where n.total_score > 0
  ), page as (
    select * from ranked order by position limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position, 'user_id', p.user_id, 'user_name', p.user_name,
        'photo_url', p.photo_url, 'total_score', p.total_score,
        'correct_answers', p.correct_answers,
        'perfect_quizzes', p.perfect_quizzes,
        'quizzes_completed', p.quizzes_completed,
        'is_viewer', p.user_id = actor::text
      ) order by p.position) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'total_score', r.total_score,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
    'entries', entries, 'viewer', viewer);
end;
$$;
revoke all on function public.list_quiz_ranking(text, text, integer) from public, anon;
grant execute on function public.list_quiz_ranking(text, text, integer) to authenticated;
