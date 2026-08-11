-- Make Bible streaks server-authoritative, keep scheduled Daily Word / quiz
-- content reviewable before release, and make quiz question replacement atomic.

alter table public.users
  add column if not exists "notifyBibleStreak" boolean not null default true;

alter table public.bible_streaks
  add column if not exists last_reminder_date date;

-- These rows are generated ahead of time and become public only at their
-- existing available_at/publish_date.  Regeneration never changes that slot.
alter table public.daily_motivations
  drop constraint if exists daily_motivations_status_check;
alter table public.daily_motivations
  add constraint daily_motivations_status_check
  check (status in ('draft', 'scheduled', 'published', 'failed', 'unpublished'));

alter table public.daily_bible_quizzes
  drop constraint if exists daily_bible_quizzes_status_check;
alter table public.daily_bible_quizzes
  add constraint daily_bible_quizzes_status_check
  check (status in ('draft', 'scheduled', 'published', 'failed', 'unpublished', 'archived'));

create or replace function public.get_my_bible_streak_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := timezone('America/Jamaica', now())::date;
  v_row public.bible_streaks;
  v_effective_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_row
  from public.bible_streaks
  where user_id = auth.uid()
  for update;

  if not found then
    return jsonb_build_object(
      'count', 0,
      'completed_today', false,
      'last_read_date', null,
      'jamaica_date', v_today
    );
  end if;

  v_effective_count := case
    when v_row.last_read_date >= v_today - 1 then greatest(v_row.streak_count, 0)
    else 0
  end;

  -- Persist the reset as well as reporting it. This keeps every client and
  -- the leaderboard consistent even if the midnight maintenance job was late.
  if v_effective_count = 0 and v_row.streak_count <> 0 then
    update public.bible_streaks
       set streak_count = 0,
           updated_at = now()
     where user_id = auth.uid();
  end if;

  return jsonb_build_object(
    'count', v_effective_count,
    'completed_today', v_row.last_read_date = v_today,
    'last_read_date', v_row.last_read_date,
    'jamaica_date', v_today
  );
end;
$$;

create or replace function public.record_my_bible_reading()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := timezone('America/Jamaica', now())::date;
  v_church_id text;
  v_display_name text;
  v_photo_url text;
  v_existing public.bible_streaks;
  v_saved public.bible_streaks;
  v_next_count integer;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select
    nullif(u."placeId", ''),
    coalesce(nullif(trim(u."fullName"), ''), nullif(trim(u.email), ''), 'Member'),
    u."photoUrl"
  into v_church_id, v_display_name, v_photo_url
  from public.users u
  where u.id = auth.uid() or u.uid = auth.uid()::text
  limit 1;

  v_church_id := coalesce(
    nullif(public.viewer_effective_church_id(), ''),
    nullif(v_church_id, ''),
    public.grace_connect_global_church_id()
  );
  v_display_name := coalesce(nullif(v_display_name, ''), auth.jwt()->>'email', 'Member');

  -- The row lock makes two devices (or two delayed retries) count today once.
  select * into v_existing
  from public.bible_streaks
  where user_id = auth.uid()
  for update;

  v_next_count := case
    when v_existing.user_id is null then 1
    when v_existing.last_read_date = v_today then greatest(v_existing.streak_count, 1)
    when v_existing.last_read_date = v_today - 1 then greatest(v_existing.streak_count, 0) + 1
    else 1
  end;

  insert into public.bible_streaks (
    user_id,
    church_id,
    user_name,
    photo_url,
    streak_count,
    last_read_date,
    last_reminder_date,
    updated_at
  ) values (
    auth.uid(),
    v_church_id,
    v_display_name,
    v_photo_url,
    v_next_count,
    v_today,
    null,
    now()
  )
  on conflict (user_id) do update
    set church_id = excluded.church_id,
        user_name = excluded.user_name,
        photo_url = excluded.photo_url,
        streak_count = v_next_count,
        last_read_date = v_today,
        last_reminder_date = null,
        updated_at = now()
  returning * into v_saved;

  return jsonb_build_object(
    'count', v_saved.streak_count,
    'completed_today', true,
    'last_read_date', v_saved.last_read_date,
    'jamaica_date', v_today
  );
end;
$$;

-- Keep the legacy signature safe for older Play Store builds. Client-supplied
-- counts/dates are intentionally ignored so an old device cannot overwrite a
-- newer server streak.
create or replace function public.upsert_my_bible_streak(
  streak_count integer,
  last_read_date date
)
returns public.bible_streaks
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_row public.bible_streaks;
begin
  v_result := public.record_my_bible_reading();
  select * into v_row from public.bible_streaks where user_id = auth.uid();
  return v_row;
end;
$$;

create or replace function public.list_bible_streak_leaderboard(
  result_limit integer default 25
)
returns table (
  user_id text,
  user_name text,
  photo_url text,
  streak_count integer,
  last_read_date date
)
language sql
stable
security definer
set search_path = public
as $$
  with clock as (
    select timezone('America/Jamaica', now())::date as today
  )
  select
    bs.user_id::text,
    bs.user_name,
    bs.photo_url,
    bs.streak_count,
    bs.last_read_date
  from public.bible_streaks bs
  cross join clock c
  where bs.church_id = public.grace_connect_leaderboard_church_id()
    and bs.last_read_date >= c.today - 1
    and bs.streak_count > 0
  order by bs.streak_count desc, bs.last_read_date desc, bs.updated_at desc
  limit greatest(1, least(coalesce(result_limit, 25), 100));
$$;

grant execute on function public.get_my_bible_streak_status() to authenticated;
grant execute on function public.record_my_bible_reading() to authenticated;
grant execute on function public.upsert_my_bible_streak(integer, date) to authenticated;
grant execute on function public.list_bible_streak_leaderboard(integer) to authenticated;

-- The Edge Function calls this with the service role. Performing delete + all
-- inserts in one database transaction prevents members from seeing a partial
-- quiz and rolls the old questions back if any replacement fails validation.
create or replace function public.replace_daily_bible_quiz_questions(
  p_quiz_id uuid,
  p_questions jsonb,
  p_generation_source text,
  p_generation_status text,
  p_validation_notes text default null,
  p_status text default null
)
returns public.daily_bible_quizzes
language plpgsql
security definer
set search_path = public
as $$
declare
  v_quiz public.daily_bible_quizzes;
  v_question jsonb;
  v_count integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) <> 5 then
    raise exception 'Exactly five quiz questions are required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
  for update;
  if not found then raise exception 'Quiz not found'; end if;

  if exists (select 1 from public.quiz_attempts where quiz_id = p_quiz_id) then
    raise exception 'A quiz with member attempts cannot be regenerated';
  end if;
  if p_status = 'scheduled'
     and (v_quiz.status = 'published' or v_quiz.available_at <= now()) then
    raise exception 'The quiz release window has started and can no longer be refreshed';
  end if;

  delete from public.daily_bible_quiz_questions where quiz_id = p_quiz_id;
  for v_question in select value from jsonb_array_elements(p_questions)
  loop
    v_count := v_count + 1;
    insert into public.daily_bible_quiz_questions (
      quiz_id, question_order, question_text,
      option_a, option_b, option_c, option_d,
      correct_option_index, correct_answer, explanation,
      scripture_references, category, difficulty, question_hash
    ) values (
      p_quiz_id,
      v_count,
      trim(v_question->>'question'),
      trim(v_question->'options'->>0),
      trim(v_question->'options'->>1),
      trim(v_question->'options'->>2),
      trim(v_question->'options'->>3),
      (v_question->>'correct_option_index')::integer,
      trim(v_question->>'correct_answer'),
      trim(v_question->>'explanation'),
      coalesce(v_question->'scripture_references', '[]'::jsonb),
      nullif(trim(v_question->>'category'), ''),
      nullif(trim(v_question->>'difficulty'), ''),
      trim(v_question->>'question_hash')
    );
  end loop;

  update public.daily_bible_quizzes
     set generation_source = p_generation_source,
         generation_status = p_generation_status,
         validation_notes = p_validation_notes,
         status = coalesce(p_status, status),
         notification_sent_at = case
           when coalesce(p_status, status) = 'scheduled' then null
           else notification_sent_at
         end,
         updated_at = now()
   where id = p_quiz_id
  returning * into v_quiz;
  return v_quiz;
end;
$$;

revoke all on function public.replace_daily_bible_quiz_questions(uuid, jsonb, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.replace_daily_bible_quiz_questions(uuid, jsonb, text, text, text, text)
  to service_role;

-- A sanitized developer feed: question text/options are reviewable, but the
-- answer index, answer text, and explanation never leave this RPC.
create or replace function public.developer_list_scheduled_content(
  p_days integer default 14
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dev public.developer_accounts;
  v_today date := timezone('America/Jamaica', now())::date;
  v_days integer := greatest(1, least(coalesce(p_days, 14), 60));
begin
  select * into v_dev from public.require_developer(null);

  return jsonb_build_object(
    'jamaica_date', v_today,
    'daily_words', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'publish_date', d.publish_date,
        'release_at', (d.publish_date::timestamp + time '05:00') at time zone 'America/Jamaica',
        'title', d.title,
        'message', d.message,
        'scripture_reference', d.scripture_reference,
        'topic', d.topic,
        'source', d.source,
        'status', d.status
      ) order by d.publish_date)
      from public.daily_motivations d
      where d.publish_date between v_today and v_today + v_days
    ), '[]'::jsonb),
    'quizzes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'church_id', q.church_id,
        'quiz_date', q.quiz_date,
        'release_at', q.available_at,
        'status', q.status,
        'source', q.generation_source,
        'generation_status', q.generation_status,
        'questions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'order', qq.question_order,
            'question', qq.question_text,
            'options', jsonb_build_array(qq.option_a, qq.option_b, qq.option_c, qq.option_d),
            'category', qq.category,
            'difficulty', qq.difficulty
          ) order by qq.question_order)
          from public.daily_bible_quiz_questions qq
          where qq.quiz_id = q.id
        ), '[]'::jsonb)
      ) order by q.quiz_date, q.church_id)
      from public.daily_bible_quizzes q
      where q.quiz_date between v_today and v_today + v_days
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.developer_list_scheduled_content(integer) to authenticated;

-- Midnight is a maintenance backstop. Reads and leaderboard queries also
-- calculate the effective value, so a delayed cron can never show stale days.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'bible-streak-midnight-reset') then
    perform cron.unschedule('bible-streak-midnight-reset');
  end if;
  if exists (select 1 from cron.job where jobname = 'bible-streak-8pm-reminder') then
    perform cron.unschedule('bible-streak-8pm-reminder');
  end if;
  if exists (select 1 from cron.job where jobname = 'daily-content-evening-preparation') then
    perform cron.unschedule('daily-content-evening-preparation');
  end if;
end $$;

select cron.schedule(
  'bible-streak-midnight-reset',
  '5 5 * * *',
  $$
    update public.bible_streaks
       set streak_count = 0,
           updated_at = now()
     where streak_count <> 0
       and last_read_date < timezone('America/Jamaica', now())::date - 1;
  $$
);

select cron.schedule(
  'bible-streak-8pm-reminder',
  '0 1 * * *',
  $$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/send-bible-streak-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret' limit 1),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $$
);

-- At 8:15 PM Jamaica, prepare tomorrow's exact content. Existing 5 AM / 7 AM
-- jobs remain the release jobs and must publish these same rows unchanged.
select cron.schedule(
  'daily-content-evening-preparation',
  '15 1 * * *',
  $$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/generate-daily-motivation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'daily_motivation_cron_secret' limit 1),
        ''
      )
    ),
    body := '{"action":"prepare"}'::jsonb
  );
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/generate-daily-bible-quiz',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret' limit 1),
        ''
      )
    ),
    body := '{"action":"prepare"}'::jsonb
  );
  $$
);
