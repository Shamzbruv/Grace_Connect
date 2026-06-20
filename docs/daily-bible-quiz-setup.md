# Daily Bible Quiz Setup

Grace Connect now has a secure Daily Bible Quiz foundation:

- One five-question quiz per church per Jamaica day.
- One attempt per member per day.
- 30 seconds per question.
- Server-side scoring only.
- App backgrounding/closing abandons the attempt.
- Church-only monthly leaderboard.
- Top-three monthly winner snapshots.

## Required Supabase Edge Function Secrets

- `HF_TOKEN`
- `DAILY_QUIZ_CRON_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON` for real lock-screen push delivery

`HF_TOKEN` and `DAILY_QUIZ_CRON_SECRET` must never be placed in Flutter, GitHub, database rows, or API responses.

## Deploy

Apply migrations. They create the quiz tables and schedule the daily quiz, stale-attempt cleanup, and monthly winner finalizer jobs:

```bash
supabase db push
```

Deploy functions:

```bash
supabase functions deploy generate-daily-bible-quiz
supabase functions deploy get-daily-bible-quiz-status
supabase functions deploy start-daily-bible-quiz
supabase functions deploy heartbeat-daily-bible-quiz
supabase functions deploy submit-daily-bible-quiz-answer
supabase functions deploy abandon-daily-bible-quiz
supabase functions deploy get-church-quiz-leaderboard
supabase functions deploy cleanup-daily-bible-quiz-attempts
supabase functions deploy finalize-monthly-quiz-winners
```

Cron functions are protected by `x-cron-secret` and have `verify_jwt = false` in `supabase/config.toml`. Member gameplay functions still require Supabase Auth.

## Vault Values

Store these in Supabase Vault:

- `grace_connect_project_url`: `https://nimgsgnkcvddomrgkawb.supabase.co`
- `daily_quiz_cron_secret`: the same value as `DAILY_QUIZ_CRON_SECRET`

Example:

```sql
select vault.create_secret('https://nimgsgnkcvddomrgkawb.supabase.co', 'grace_connect_project_url');
select vault.create_secret('YOUR_LONG_RANDOM_SECRET', 'daily_quiz_cron_secret');
```

## Cron Jobs

The migration creates these schedules automatically. Use the SQL below only if you need to recreate the jobs manually. Enable extensions:

```sql
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;
```

Daily quiz refresh at 7:00 AM Jamaica time:

```sql
select cron.schedule(
  'daily-bible-quiz-7am-jamaica',
  '0 12 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url') || '/functions/v1/generate-daily-bible-quiz',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

Stale-attempt cleanup every minute:

```sql
select cron.schedule(
  'daily-bible-quiz-stale-attempt-cleanup',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url') || '/functions/v1/cleanup-daily-bible-quiz-attempts',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

Monthly top-three snapshot at 12:05 AM Jamaica time on the first day of every month. This finalizes the month that just ended:

```sql
select cron.schedule(
  'daily-bible-quiz-monthly-winners',
  '5 5 1 * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url') || '/functions/v1/finalize-monthly-quiz-winners',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'daily_quiz_cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

## Manual Test

Generate today’s quizzes:

```bash
curl -i -X POST \
  https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/generate-daily-bible-quiz \
  -H "Content-Type: application/json" \
  -H "x-cron-secret: YOUR_DAILY_QUIZ_CRON_SECRET" \
  -d '{}'
```

Then sign in through the app and open Bible → Quiz.

## Verify

Check:

- `daily_bible_quizzes` has one published row per church/date.
- `daily_bible_quiz_questions` has exactly five rows per quiz.
- Members cannot directly read question answers before submission.
- `quiz_attempts` rejects a second attempt for the same quiz/member.
- `quiz_attempt_answers` has one row per answered question.
- `system_notification_outbox` records push delivery attempts.
- `monthly_quiz_winners` is populated by the monthly job.

## Push Notification Test

For real lock-screen notifications, add `FIREBASE_SERVICE_ACCOUNT_JSON` as a Supabase Edge Function secret. It must be the full Firebase service-account JSON for the Firebase project that owns the app’s FCM configuration.

Without that secret, the app still creates quizzes and in-app notifications, but push rows are marked `skipped` in `system_notification_outbox`.

## Limitations

Mobile operating systems do not guarantee that an app can make a network call when force-closed. Grace Connect handles this by calling `abandon-daily-bible-quiz` when lifecycle events fire and by running the stale heartbeat cleanup every minute. This is the strongest realistic approach, but no app can guarantee perfect detection for every OS-level force close.
