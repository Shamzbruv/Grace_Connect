-- Server-side schedules for Daily Word and Daily Bible Quiz.
-- Supabase cron uses UTC. Jamaica is UTC-5 year-round.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-bible-quiz-yearly-winners') then
    perform cron.unschedule('daily-bible-quiz-yearly-winners');
  end if;

  if exists (select 1 from cron.job where jobname = 'daily-bible-quiz-monthly-winners') then
    perform cron.unschedule('daily-bible-quiz-monthly-winners');
  end if;

  if exists (select 1 from cron.job where jobname = 'daily-bible-quiz-7am-jamaica') then
    perform cron.unschedule('daily-bible-quiz-7am-jamaica');
  end if;

  if exists (select 1 from cron.job where jobname = 'daily-bible-quiz-stale-attempt-cleanup') then
    perform cron.unschedule('daily-bible-quiz-stale-attempt-cleanup');
  end if;

  if exists (select 1 from cron.job where jobname = 'daily-motivation-5am-jamaica') then
    perform cron.unschedule('daily-motivation-5am-jamaica');
  end if;
end $$;

select cron.schedule(
  'daily-motivation-5am-jamaica',
  '0 10 * * *',
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
    body := '{}'::jsonb
  );
  $$
);

select cron.schedule(
  'daily-bible-quiz-7am-jamaica',
  '0 12 * * *',
  $$
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
    body := '{}'::jsonb
  );
  $$
);

select cron.schedule(
  'daily-bible-quiz-stale-attempt-cleanup',
  '* * * * *',
  $$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/cleanup-daily-bible-quiz-attempts',
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

select cron.schedule(
  'daily-bible-quiz-monthly-winners',
  '5 5 1 * *',
  $$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/finalize-monthly-quiz-winners',
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
