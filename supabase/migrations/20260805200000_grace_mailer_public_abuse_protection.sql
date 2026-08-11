-- Atomically rate-limit the public signup and password-reset mail actions.
-- Only irreversible SHA-256 keys are retained; raw email and IP addresses are
-- never written to this table.

create table if not exists public.grace_mail_public_rate_events (
  id bigint generated always as identity primary key,
  action text not null
    check (action in ('auth-signup', 'password-reset')),
  email_key text not null
    check (email_key ~ '^[a-f0-9]{64}$'),
  ip_key text
    check (ip_key is null or ip_key ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now()
);

create index if not exists grace_mail_rate_action_created_idx
  on public.grace_mail_public_rate_events (action, created_at desc);

create index if not exists grace_mail_rate_email_created_idx
  on public.grace_mail_public_rate_events (action, email_key, created_at desc);

create index if not exists grace_mail_rate_ip_created_idx
  on public.grace_mail_public_rate_events (action, ip_key, created_at desc)
  where ip_key is not null;

alter table public.grace_mail_public_rate_events enable row level security;
revoke all on public.grace_mail_public_rate_events
from public, anon, authenticated;
grant all on public.grace_mail_public_rate_events to service_role;

create or replace function public.consume_grace_mail_public_rate_limit(
  target_action text,
  target_email_key text,
  target_ip_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  normalized_action text := lower(trim(coalesce(target_action, '')));
  normalized_email_key text := lower(trim(coalesce(target_email_key, '')));
  normalized_ip_key text := nullif(lower(trim(coalesce(target_ip_key, ''))), '');
  checked_at timestamptz := clock_timestamp();
  recent_count integer := 0;
  oldest_event timestamptz;
  email_hour_limit integer;
  ip_ten_minute_limit integer;
  ip_day_limit integer;
  global_hour_limit integer;
  global_day_limit integer;
  retry_after integer := 1;
begin
  if normalized_action not in ('auth-signup', 'password-reset') then
    raise exception 'Unsupported public mail action';
  end if;
  if normalized_email_key !~ '^[a-f0-9]{64}$' then
    raise exception 'Email rate-limit key is invalid';
  end if;
  if normalized_ip_key is not null
     and normalized_ip_key !~ '^[a-f0-9]{64}$' then
    raise exception 'IP rate-limit key is invalid';
  end if;

  if normalized_action = 'auth-signup' then
    email_hour_limit := 3;
    ip_ten_minute_limit := 10;
    ip_day_limit := 40;
    global_hour_limit := 120;
    global_day_limit := 600;
  else
    email_hour_limit := 3;
    ip_ten_minute_limit := 12;
    ip_day_limit := 60;
    global_hour_limit := 180;
    global_day_limit := 900;
  end if;

  -- A fixed lock order makes each check-and-consume operation atomic across
  -- concurrent Edge Function instances without holding a table-level lock.
  perform pg_advisory_xact_lock(
    hashtextextended('grace-mail:global:' || normalized_action, 0)
  );
  perform pg_advisory_xact_lock(
    hashtextextended(
      'grace-mail:email:' || normalized_action || ':' || normalized_email_key,
      0
    )
  );
  if normalized_ip_key is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(
        'grace-mail:ip:' || normalized_action || ':' || normalized_ip_key,
        0
      )
    );
  end if;

  delete from public.grace_mail_public_rate_events
  where action = normalized_action
    and created_at < checked_at - interval '7 days';

  select count(*)::integer, min(created_at)
  into recent_count, oldest_event
  from public.grace_mail_public_rate_events
  where action = normalized_action
    and email_key = normalized_email_key
    and created_at >= checked_at - interval '1 minute';
  if recent_count >= 1 then
    retry_after := greatest(
      1,
      ceil(extract(epoch from oldest_event + interval '1 minute' - checked_at))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'reason', 'email_cooldown',
      'retry_after_seconds', retry_after
    );
  end if;

  select count(*)::integer, min(created_at)
  into recent_count, oldest_event
  from public.grace_mail_public_rate_events
  where action = normalized_action
    and email_key = normalized_email_key
    and created_at >= checked_at - interval '1 hour';
  if recent_count >= email_hour_limit then
    retry_after := greatest(
      1,
      ceil(extract(epoch from oldest_event + interval '1 hour' - checked_at))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'reason', 'email_hourly_limit',
      'retry_after_seconds', retry_after
    );
  end if;

  if normalized_ip_key is not null then
    select count(*)::integer, min(created_at)
    into recent_count, oldest_event
    from public.grace_mail_public_rate_events
    where action = normalized_action
      and ip_key = normalized_ip_key
      and created_at >= checked_at - interval '10 minutes';
    if recent_count >= ip_ten_minute_limit then
      retry_after := greatest(
        1,
        ceil(extract(epoch from oldest_event + interval '10 minutes' - checked_at))::integer
      );
      return jsonb_build_object(
        'allowed', false,
        'reason', 'ip_burst_limit',
        'retry_after_seconds', retry_after
      );
    end if;

    select count(*)::integer, min(created_at)
    into recent_count, oldest_event
    from public.grace_mail_public_rate_events
    where action = normalized_action
      and ip_key = normalized_ip_key
      and created_at >= checked_at - interval '1 day';
    if recent_count >= ip_day_limit then
      retry_after := greatest(
        1,
        ceil(extract(epoch from oldest_event + interval '1 day' - checked_at))::integer
      );
      return jsonb_build_object(
        'allowed', false,
        'reason', 'ip_daily_limit',
        'retry_after_seconds', retry_after
      );
    end if;
  end if;

  select count(*)::integer, min(created_at)
  into recent_count, oldest_event
  from public.grace_mail_public_rate_events
  where action = normalized_action
    and created_at >= checked_at - interval '1 hour';
  if recent_count >= global_hour_limit then
    retry_after := greatest(
      1,
      ceil(extract(epoch from oldest_event + interval '1 hour' - checked_at))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'reason', 'global_hourly_limit',
      'retry_after_seconds', retry_after
    );
  end if;

  select count(*)::integer, min(created_at)
  into recent_count, oldest_event
  from public.grace_mail_public_rate_events
  where action = normalized_action
    and created_at >= checked_at - interval '1 day';
  if recent_count >= global_day_limit then
    retry_after := greatest(
      1,
      ceil(extract(epoch from oldest_event + interval '1 day' - checked_at))::integer
    );
    return jsonb_build_object(
      'allowed', false,
      'reason', 'global_daily_limit',
      'retry_after_seconds', retry_after
    );
  end if;

  insert into public.grace_mail_public_rate_events (
    action,
    email_key,
    ip_key,
    created_at
  ) values (
    normalized_action,
    normalized_email_key,
    normalized_ip_key,
    checked_at
  );

  return jsonb_build_object(
    'allowed', true,
    'retry_after_seconds', 0
  );
end;
$$;

revoke all on function public.consume_grace_mail_public_rate_limit(text, text, text)
from public, anon, authenticated;
grant execute on function public.consume_grace_mail_public_rate_limit(text, text, text)
to service_role;

comment on table public.grace_mail_public_rate_events is
  'Short-lived hashed counters used to prevent public mail endpoint abuse.';
comment on function public.consume_grace_mail_public_rate_limit(text, text, text) is
  'Atomically consumes signup/reset mail quotas for one hashed email and IP.';

select pg_notify('pgrst', 'reload schema');
