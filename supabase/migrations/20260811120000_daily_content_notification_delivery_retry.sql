-- Forward-only retry state for Daily Word and Bible Quiz notification delivery.
-- The content reliability migration was already applied before this lease was
-- added, so keep this repair in its own migration.

alter table public.daily_motivations
  add column if not exists notification_claimed_at timestamptz;

alter table public.daily_bible_quizzes
  add column if not exists notification_claimed_at timestamptz;

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
  if jsonb_typeof(p_questions) <> 'array'
      or jsonb_array_length(p_questions) <> 5 then
    raise exception 'Exactly five quiz questions are required';
  end if;

  select * into v_quiz
  from public.daily_bible_quizzes
  where id = p_quiz_id
  for update;
  if not found then raise exception 'Quiz not found'; end if;

  if exists (
    select 1 from public.quiz_attempts where quiz_id = p_quiz_id
  ) then
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
         notification_claimed_at = case
           when coalesce(p_status, status) = 'scheduled' then null
           else notification_claimed_at
         end,
         updated_at = now()
   where id = p_quiz_id
  returning * into v_quiz;
  return v_quiz;
end;
$$;

revoke all on function public.replace_daily_bible_quiz_questions(
  uuid, jsonb, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.replace_daily_bible_quiz_questions(
  uuid, jsonb, text, text, text, text
) to service_role;

do $$
begin
  if exists (
    select 1 from cron.job
    where jobname = 'daily-motivation-delivery-retry'
  ) then
    perform cron.unschedule('daily-motivation-delivery-retry');
  end if;
  if exists (
    select 1 from cron.job
    where jobname = 'daily-bible-quiz-delivery-retry'
  ) then
    perform cron.unschedule('daily-bible-quiz-delivery-retry');
  end if;
end;
$$;

-- 10:15/12:15 UTC are 5:15/7:15 AM Jamaica. A second release invocation
-- reclaims a failed or crashed lease. Shared in-app/outbox guards make retries
-- idempotent after either side of delivery already succeeded.
select cron.schedule(
  'daily-motivation-delivery-retry',
  '15 10 * * *',
  $cron$
  select net.http_post(
    url := coalesce(
      (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'grace_connect_project_url'
        limit 1
      ),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/generate-daily-motivation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'daily_motivation_cron_secret'
          limit 1
        ),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $cron$
);

select cron.schedule(
  'daily-bible-quiz-delivery-retry',
  '15 12 * * *',
  $cron$
  select net.http_post(
    url := coalesce(
      (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'grace_connect_project_url'
        limit 1
      ),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/generate-daily-bible-quiz',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'daily_quiz_cron_secret'
          limit 1
        ),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $cron$
);
