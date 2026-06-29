-- Private deployment marker.
-- The live project used this migration version to configure attendance_cron_secret
-- in Supabase Vault. The secret value is intentionally not stored in the repo.
-- For a new Supabase environment, create a matching Edge secret named
-- ATTENDANCE_CRON_SECRET and a Vault secret named attendance_cron_secret.
select 1;
