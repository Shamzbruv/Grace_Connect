# Daily Word Setup

Grace Connect now has a secure Daily Word pipeline.

## Required Supabase Edge Function Secrets

- `HF_TOKEN`
- `DAILY_MOTIVATION_CRON_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON` for real lock-screen push delivery

`HF_TOKEN` must stay only in Supabase Edge Function Secrets. Do not put it in Flutter, GitHub, database rows, or client environment files.

## Deploy

Apply the migrations. They create the tables and schedule the 5:00 AM Jamaica cron job:

```bash
supabase db push
```

Deploy the function:

```bash
supabase functions deploy generate-daily-motivation
```

The cron function has `verify_jwt = false` in `supabase/config.toml`, but it still requires the `x-cron-secret` header.

## Vault Values

Store these in Supabase Vault:

- `grace_connect_project_url`: `https://nimgsgnkcvddomrgkawb.supabase.co`
- `daily_motivation_cron_secret`: the same value as `DAILY_MOTIVATION_CRON_SECRET`

Example:

```sql
select vault.create_secret('https://nimgsgnkcvddomrgkawb.supabase.co', 'grace_connect_project_url');
select vault.create_secret('YOUR_LONG_RANDOM_SECRET', 'daily_motivation_cron_secret');
```

## Cron

Daily Word runs at 5:00 AM Jamaica time, which is 10:00 UTC. The migration schedules this as `daily-motivation-5am-jamaica`; use this SQL only if you need to recreate the job manually.

```sql
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

select cron.schedule(
  'daily-word-5am-jamaica',
  '0 10 * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url') || '/functions/v1/generate-daily-motivation',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'daily_motivation_cron_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

## Manual Test

```bash
curl -i -X POST \
  https://nimgsgnkcvddomrgkawb.supabase.co/functions/v1/generate-daily-motivation \
  -H "Content-Type: application/json" \
  -H "x-cron-secret: YOUR_DAILY_MOTIVATION_CRON_SECRET" \
  -d '{}'
```

Run it twice. The second run should report that today’s message already exists or should not duplicate the notification.

## Confirm

Check:

- `daily_motivations` has one row for the Jamaica date.
- `system_notification_outbox` has one row per church devotional topic.
- `notifications` has in-app notification rows for users with `notifyDailyMotivation = true`.
- If `FIREBASE_SERVICE_ACCOUNT_JSON` is set, outbox status should become `sent`.

## Rotate Secrets

To rotate:

1. Create a new random value.
2. Update the Supabase Edge Function secret.
3. Update the matching Supabase Vault secret.
4. Redeploy the function if required by your Supabase setup.
5. Manually test once.
