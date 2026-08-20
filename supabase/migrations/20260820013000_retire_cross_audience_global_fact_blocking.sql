-- The Daily Bible Quiz architecture changed: Grace Connect Global and every
-- church are now meant to always see the identical quiz (one canonical
-- generation per day, mirrored to every audience), not independently
-- generated variants. The pop-quiz-day rule that treated Global's picked
-- facts as blocking every church's own generation (and vice versa) was
-- written for the OLD architecture, where different audiences legitimately
-- needed different content and had to avoid accidentally repeating each
-- other's facts.
--
-- Under the new architecture that cross-audience check is not just
-- unnecessary, it actively breaks mirroring: when a church legitimately
-- copies Global's exact quiz, the fact-conflict guard sees Global's own
-- facts already claimed by "another audience" (itself, by the old rule) and
-- rejects the write every time on a pop-quiz day -- confirmed in production
-- for 2026-08-20's prepare cycle, where every fact in Global's scheduled
-- quiz ("matthew 9::tax", "genesis 25::grandson", etc.) blocked the mirrored
-- insert for a church that has never seen those facts before.
--
-- The 20260819235000 migration already made this the rule on chapter-study
-- days; this migration makes it the rule everywhere, all the time. Blocking
-- is now purely about an audience's own retained history (never repeat a
-- fact this specific audience already used on a previous day) -- it is no
-- longer about keeping different audiences from ending up with overlapping
-- facts, since overlapping (identical) content is now the explicit goal.

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

  if exists (
    select 1
    from public.daily_bible_quiz_questions qq
    join public.daily_bible_quizzes q on q.id = qq.quiz_id
    where (q.status = 'scheduled' or q.first_published_at is not null)
      and cardinality(qq.fact_keys) = 0
      and q.church_id = p_church_id
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
    and q.church_id = p_church_id
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
begin
  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id;
  if not found then
    raise exception 'Quiz not found';
  end if;

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
      and q.church_id = v_quiz.church_id
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
      and q.church_id = v_quiz.church_id
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
