-- On a chapter-study day (Mon/Wed/Sat), every audience -- Grace Connect
-- Global and every individual church -- is deliberately assigned the SAME
-- linked Daily Word chapter, so they all have to draw their 5 quiz facts
-- from the same small pool of verses. Treating Global's picks as blocking
-- every church's generation (and vice versa) meant N simultaneous audiences
-- needed 5*N mutually-exclusive facts out of ONE chapter on the same day --
-- which a normal-length chapter genuinely cannot support. This is what was
-- failing in production: Global would generate first and claim 5 facts,
-- then the church-specific run would fail every single retry for the rest
-- of the day trying to find 5 *more*, distinct facts from the same chapter.
--
-- On a chapter-study day, only an audience's own prior history should block
-- it -- there is nothing wrong with a church's quiz and Global's quiz
-- covering the same chapter the same way, since every audience is studying
-- that same chapter that day by design. Pop-quiz days (drawn from the whole
-- Bible, no shared-chapter constraint) keep the original cross-audience
-- sharing, since there's no artificial competition for a limited pool there.

create or replace function public.get_blocked_daily_bible_quiz_fact_keys(
  p_church_id text,
  p_quiz_date date
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_strict boolean := true;
  v_relaxed_days integer := 60;
  v_chapter_study boolean := false;
  v_keys text[];
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if nullif(trim(coalesce(p_church_id, '')), '') is null
      or p_quiz_date is null then
    raise exception 'Church and quiz date are required';
  end if;

  select
    coalesce(quiz_guarantee_unique, true),
    greatest(1, least(coalesce(relaxed_quiz_history_days, 60), 3650))
  into v_strict, v_relaxed_days
  from public.daily_content_generation_settings
  where id = true;

  select coalesce(has_study_quiz, false) into v_chapter_study
  from public.daily_motivations
  where publish_date = p_quiz_date;

  if exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where (q.status = 'scheduled' or q.first_published_at is not null)
      and cardinality(qq.fact_keys) = 0
      and (
        q.church_id = p_church_id
        or (not v_chapter_study and q.church_id = 'grace_connect_global')
      )
      and (
        v_strict
        or (
          q.quiz_date >= p_quiz_date - v_relaxed_days
          and q.quiz_date <= p_quiz_date
        )
      )
  ) then
    raise exception 'Quiz uniqueness cannot verify malformed retained quiz history';
  end if;

  select coalesce(array_agg(distinct fact_key order by fact_key), array[]::text[])
    into v_keys
  from public.daily_bible_quiz_questions qq
  join public.daily_bible_quizzes q on q.id = qq.quiz_id
  cross join lateral unnest(qq.fact_keys) as fact_key
  where (q.status = 'scheduled' or q.first_published_at is not null)
    and (
      q.church_id = p_church_id
      or (not v_chapter_study and q.church_id = 'grace_connect_global')
    )
    and (
      v_strict
      or (
        q.quiz_date >= p_quiz_date - v_relaxed_days
        and q.quiz_date <= p_quiz_date
      )
    );
  return v_keys;
end;
$$;

create or replace function public.daily_bible_quiz_has_fact_conflict(
  p_quiz_id uuid,
  p_fact_keys text[]
)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
  v_strict boolean := true;
  v_relaxed_days integer := 60;
  v_chapter_study boolean;
begin
  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id;
  if not found then
    raise exception 'Quiz not found';
  end if;

  v_chapter_study := v_quiz.quiz_mode = 'chapter_study';

  select
    coalesce(quiz_guarantee_unique, true),
    greatest(1, least(coalesce(relaxed_quiz_history_days, 60), 3650))
    into v_strict, v_relaxed_days
  from public.daily_content_generation_settings
  where id = true;

  if exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where q.id <> p_quiz_id
      and (q.status = 'scheduled' or q.first_published_at is not null)
      and cardinality(qq.fact_keys) = 0
      and (
        q.church_id = v_quiz.church_id
        or (not v_chapter_study and q.church_id = 'grace_connect_global')
      )
      and (
        v_strict
        or (
          q.quiz_date >= v_quiz.quiz_date - v_relaxed_days
          and q.quiz_date <= v_quiz.quiz_date
        )
      )
  ) then
    raise exception 'Strict quiz uniqueness cannot verify malformed retained quiz history';
  end if;

  return exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where q.id <> p_quiz_id
      and (q.status = 'scheduled' or q.first_published_at is not null)
      and qq.fact_keys && p_fact_keys
      and (
        q.church_id = v_quiz.church_id
        or (not v_chapter_study and q.church_id = 'grace_connect_global')
      )
      and (
        v_strict
        or (
          q.quiz_date >= v_quiz.quiz_date - v_relaxed_days
          and q.quiz_date <= v_quiz.quiz_date
        )
      )
  );
end;
$$;
