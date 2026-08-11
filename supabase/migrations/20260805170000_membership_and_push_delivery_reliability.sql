-- Make push delivery independently addressable per installation and repair the
-- church-member approval permission gate. Topic subscriptions remain as a
-- backwards-compatible fallback for app versions released before this table.

create table if not exists public.push_device_registrations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null unique,
  token text not null unique,
  unregister_secret_hash text not null,
  platform text not null,
  app_version text,
  topics text[] not null default '{}'::text[],
  enabled boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_device_registrations_token_length
    check (char_length(token) between 20 and 4096),
  constraint push_device_registrations_secret_hash_length
    check (char_length(unregister_secret_hash) = 32),
  constraint push_device_registrations_platform
    check (platform in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown'))
);

-- Keep the migration repair-safe if an earlier deployment created the initial
-- registry shape before this hardening was added. Existing rows receive an
-- unreachable random unregister hash and will become manageable again the next
-- time that installation registers with its device-held secret.
alter table public.push_device_registrations
  add column if not exists installation_id uuid;
alter table public.push_device_registrations
  add column if not exists unregister_secret_hash text;
update public.push_device_registrations
   set installation_id = gen_random_uuid()
 where installation_id is null;
update public.push_device_registrations
   set unregister_secret_hash = md5(gen_random_uuid()::text)
 where unregister_secret_hash is null;
alter table public.push_device_registrations
  alter column installation_id set not null;
alter table public.push_device_registrations
  alter column unregister_secret_hash set not null;

create unique index if not exists push_device_registrations_installation_idx
  on public.push_device_registrations (installation_id);

create index if not exists push_device_registrations_user_enabled_idx
  on public.push_device_registrations (user_id, enabled, last_seen_at desc);

create index if not exists push_device_registrations_topics_idx
  on public.push_device_registrations using gin (topics);

alter table public.push_device_registrations enable row level security;

drop policy if exists "Members read their push devices"
  on public.push_device_registrations;
create policy "Members read their push devices"
  on public.push_device_registrations
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "Members remove their push devices"
  on public.push_device_registrations;
create policy "Members remove their push devices"
  on public.push_device_registrations
  for delete
  to authenticated
  using (user_id = auth.uid());

revoke all on public.push_device_registrations from anon;
revoke insert, update on public.push_device_registrations from authenticated;
grant select, delete on public.push_device_registrations to authenticated;
grant all on public.push_device_registrations to service_role;

drop function if exists public.register_push_device(text, text, text, text[]);
create function public.register_push_device(
  p_token text,
  p_platform text,
  p_app_version text default null,
  p_topics text[] default '{}'::text[],
  p_installation_id uuid default null,
  p_unregister_secret text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  clean_token text := nullif(trim(coalesce(p_token, '')), '');
  clean_platform text := coalesce(
    lower(nullif(trim(coalesce(p_platform, '')), '')),
    'unknown'
  );
  clean_installation_id uuid := p_installation_id;
  clean_unregister_secret text := nullif(trim(coalesce(p_unregister_secret, '')), '');
  requested_topics text[];
  clean_topics text[];
  registration_id uuid;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if clean_token is null or char_length(clean_token) < 20 or char_length(clean_token) > 4096 then
    raise exception 'Invalid push token.';
  end if;

  if clean_installation_id is null then
    raise exception 'Installation id is required.';
  end if;

  if clean_unregister_secret is null
     or char_length(clean_unregister_secret) < 20
     or char_length(clean_unregister_secret) > 512 then
    raise exception 'Invalid installation secret.';
  end if;

  if clean_platform not in ('android', 'ios', 'macos', 'windows', 'linux', 'web', 'unknown') then
    clean_platform := 'unknown';
  end if;

  select coalesce(array_agg(topic order by topic), '{}'::text[])
    into requested_topics
  from (
    select distinct trim(candidate) as topic
    from unnest(coalesce(p_topics, '{}'::text[])) as candidate
    where trim(candidate) ~ '^[A-Za-z0-9_~%.-]{1,900}$'
    limit 64
  ) allowed_topics;

  -- p_topics expresses notification preferences, never authorization. Only
  -- topics derived from the caller's identity and active membership survive.
  -- Church aliases are accepted because released clients may carry either the
  -- churches.id or churches.placeId representation.
  with active_church_keys as (
    select distinct nullif(trim(church_key), '') as church_key
    from public.church_memberships cm
    left join public.churches c
      on c.id = cm.church_id or c."placeId" = cm.church_id
    cross join lateral unnest(array[
      cm.church_id,
      c.id,
      c."placeId"
    ]::text[]) as church_key
    where cm.user_id = actor_id
      and cm.membership_status = 'active'
      and nullif(trim(church_key), '') is not null
  ), allowed_requested_topics as (
    select requested_topic as topic
    from unnest(requested_topics) as requested_topic
    where requested_topic = 'graceconnect_all'
       or requested_topic = 'user_' || actor_id::text
       or exists (
         select 1
         from active_church_keys ack
         where requested_topic = any(array[
           'church_' || ack.church_key,
           'church_' || ack.church_key || '_events',
           'church_' || ack.church_key || '_updates',
           'church_' || ack.church_key || '_devotionals',
           'church_' || ack.church_key || '_quiz',
           'church_' || ack.church_key || '_community',
           'church_' || ack.church_key || '_prayers'
         ]::text[])
       )
       or exists (
         select 1
         from public.church_memberships cm
         left join public.churches c
           on c.id = cm.church_id or c."placeId" = cm.church_id
         cross join lateral unnest(array[
           cm.church_id,
           c.id,
           c."placeId"
         ]::text[]) as church_key
         where cm.user_id = actor_id
           and cm.membership_status = 'active'
           and requested_topic = 'church_' || church_key || '_leaders'
           and public.can_manage_church_members(cm.church_id)
       )
  )
  select coalesce(array_agg(distinct topic order by topic), '{}'::text[])
    into clean_topics
  from allowed_requested_topics;

  -- A Firebase token can survive an app-data reset while the installation id
  -- changes. Possession of the current token under an authenticated session is
  -- sufficient to retire that obsolete row before the exact-install upsert.
  delete from public.push_device_registrations
   where token = clean_token
     and installation_id <> clean_installation_id;

  insert into public.push_device_registrations (
    user_id,
    installation_id,
    token,
    unregister_secret_hash,
    platform,
    app_version,
    topics,
    enabled,
    last_seen_at,
    updated_at
  )
  values (
    actor_id,
    clean_installation_id,
    clean_token,
    md5(clean_unregister_secret),
    clean_platform,
    nullif(left(trim(coalesce(p_app_version, '')), 80), ''),
    clean_topics,
    true,
    now(),
    now()
  )
  on conflict (installation_id) do update
    set user_id = excluded.user_id,
        token = excluded.token,
        unregister_secret_hash = excluded.unregister_secret_hash,
        platform = excluded.platform,
        app_version = excluded.app_version,
        topics = excluded.topics,
        enabled = true,
        last_seen_at = now(),
        updated_at = now()
  returning id into registration_id;

  return registration_id;
end;
$$;

drop function if exists public.unregister_push_device(text);
create function public.unregister_push_device(
  p_token text,
  p_installation_id uuid,
  p_unregister_secret text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  disabled_count integer;
begin
  update public.push_device_registrations
     set enabled = false,
         topics = '{}'::text[],
         updated_at = now()
   where token = trim(coalesce(p_token, ''))
     and installation_id = p_installation_id
     and unregister_secret_hash = md5(trim(coalesce(p_unregister_secret, '')));
  get diagnostics disabled_count = row_count;
  return disabled_count > 0;
end;
$$;

revoke all on function public.register_push_device(text, text, text, text[], uuid, text)
  from public, anon;
grant execute on function public.register_push_device(text, text, text, text[], uuid, text)
  to authenticated;
grant execute on function public.unregister_push_device(text, uuid, text)
  to anon, authenticated;

-- A membership event may be retried after a transport failure, but a released
-- client must not be able to spam the same request/approval push repeatedly.
create table if not exists public.membership_push_deliveries (
  membership_id uuid not null
    references public.church_memberships(id) on delete cascade,
  event_type text not null
    check (event_type in ('membership_request_received', 'membership_approved')),
  status text not null default 'processing'
    check (status in ('processing', 'sent', 'failed')),
  attempt_count integer not null default 1 check (attempt_count > 0),
  attempted_at timestamptz not null default now(),
  completed_at timestamptz,
  error_message text,
  primary key (membership_id, event_type)
);

alter table public.membership_push_deliveries enable row level security;
revoke all on public.membership_push_deliveries from public, anon, authenticated;
grant all on public.membership_push_deliveries to service_role;

create or replace function public.claim_membership_push_delivery(
  p_membership_id uuid,
  p_event_type text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed_membership_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required.';
  end if;

  if p_event_type not in ('membership_request_received', 'membership_approved') then
    raise exception 'Unsupported membership push event.';
  end if;

  insert into public.membership_push_deliveries as delivery (
    membership_id,
    event_type,
    status,
    attempt_count,
    attempted_at,
    completed_at,
    error_message
  ) values (
    p_membership_id,
    p_event_type,
    'processing',
    1,
    now(),
    null,
    null
  )
  on conflict (membership_id, event_type) do update
    set status = 'processing',
        attempt_count = delivery.attempt_count + 1,
        attempted_at = now(),
        completed_at = null,
        error_message = null
    where delivery.status = 'failed'
       or (
         delivery.status = 'processing'
         and delivery.attempted_at < now() - interval '5 minutes'
       )
  returning membership_id into claimed_membership_id;

  return claimed_membership_id is not null;
end;
$$;

revoke all on function public.claim_membership_push_delivery(uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_membership_push_delivery(uuid, text)
  to service_role;

-- Canonicalize both church identifiers and normalize privilege spelling. The
-- old helper required an exact church_id and exact camel-case privilege, which
-- made legitimate approval requests fail when profiles used churches.placeId
-- or a role editor changed capitalization.
create or replace function public.can_manage_church_members(target_church_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  with actor as (
    select
      u.id,
      coalesce(u."appPrivileges", '{}'::text[]) as app_privileges
    from public.users u
    where u.id = auth.uid()
       or u.uid = auth.uid()::text
    limit 1
  ),
  target_church as (
    select c.id, c."placeId"
    from public.churches c
    where c.id = nullif(trim(coalesce(target_church_id, '')), '')
       or c."placeId" = nullif(trim(coalesce(target_church_id, '')), '')
    limit 1
  )
  select exists (
    select 1
    from actor a
    join public.church_memberships cm
      on cm.user_id = auth.uid()
     and cm.membership_status = 'active'
    left join target_church tc on true
    left join public.church_member_roles cmr
      on cmr.membership_id = cm.id
     and cmr.revoked_at is null
    where (
      cm.church_id = nullif(trim(coalesce(target_church_id, '')), '')
      or cm.church_id = tc.id
      or cm.church_id = tc."placeId"
    )
    and (
      public.normalize_role_name(cmr.role_name) in (
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor',
        'church_admin',
        'admin',
        'administrator',
        'secretary',
        'church_secretary'
      )
      or exists (
        select 1
        from unnest(a.app_privileges) as privilege_name
        where regexp_replace(lower(trim(privilege_name)), '[^a-z0-9]+', '', 'g')
          in ('approvemembers', 'managechurchsettings')
      )
    )
  );
$$;

grant execute on function public.can_manage_church_members(text) to authenticated;

-- The production approval routine used its `membership_id` argument as an
-- ON CONFLICT column name as well. PL/pgSQL therefore raised 42702
-- (ambiguous_column) at the role assignment step and rolled the entire
-- approval back. Keep the public RPC parameter names used by released clients,
-- but use the locked target row and qualified repair update internally.
create or replace function public.approve_church_membership(
  membership_id uuid,
  decision_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  target record;
  church_name text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into target
  from public.church_memberships
  where id = membership_id
  for update;

  if target.id is null then
    raise exception 'Membership request not found.';
  end if;
  if target.user_id = actor_id then
    raise exception 'You cannot approve your own membership.';
  end if;
  if target.membership_status <> 'pending' then
    raise exception 'Only pending memberships can be approved.';
  end if;
  if not public.can_manage_church_members(target.church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  update public.church_memberships
     set membership_status = 'active',
         reviewed_by = actor_id,
         reviewed_at = now(),
         decision_reason = nullif(trim(coalesce(decision_note, '')), '')
   where id = target.id;

  update public.church_memberships
     set membership_status = 'cancelled',
         decision_reason =
           'Cancelled because another church membership was approved.'
   where user_id = target.user_id
     and id <> target.id
     and membership_status = 'pending';

  select coalesce(nullif(display_name, ''), nullif(name, ''), target.church_id)
    into church_name
  from public.churches
  where id = target.church_id or "placeId" = target.church_id
  limit 1;

  update public.users
     set "placeId" = target.church_id,
         "placeName" = coalesce(church_name, target.church_id),
         "accountState" = 'active',
         roles = case
           when roles is null or cardinality(roles) = 0 then array['Member']
           else roles
         end
   where id = target.user_id or uid = target.user_id::text;

  insert into public.church_member_roles (
    membership_id,
    role_name,
    assigned_by
  ) values (
    target.id,
    'Member',
    actor_id
  )
  on conflict do nothing;

  -- Avoid a hard-coded production constraint name and the historical
  -- membership_id parameter/column ambiguity. The locked membership permits a
  -- conflict-safe insert followed by an explicitly qualified repair update.
  update public.church_member_roles cmr
     set revoked_at = null,
         assigned_by = actor_id,
         assigned_at = now()
   where cmr.membership_id = target.id
     and cmr.role_name = 'Member';

  update public.notifications
     set is_read = true
   where entity_table = 'church_memberships'
     and entity_id = target.id::text
     and type = 'membership_request_received';

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    church_id,
    event_type,
    details
  ) values (
    actor_id,
    target.user_id,
    target.church_id,
    'membership_approved',
    jsonb_build_object(
      'reason',
      nullif(trim(coalesce(decision_note, '')), '')
    )
  );

  begin
    perform public.create_notification(
      target.user_id,
      actor_id,
      'membership_approved',
      'Membership approved',
      'Your request to join ' || coalesce(church_name, 'this church') ||
        ' was approved.',
      target.church_id,
      'church_memberships',
      target.id::text,
      '/dashboard'
    );
  exception when undefined_function then
    null;
  end;
end;
$$;

grant execute on function public.approve_church_membership(uuid, text)
  to authenticated;

-- Ensure an approved membership always repairs the denormalized profile even
-- for legacy rows whose identity is stored in users.uid rather than users.id.
create or replace function public.sync_active_membership_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  resolved_church_name text;
begin
  if new.membership_status <> 'active'
     or (tg_op = 'UPDATE' and old.membership_status = 'active') then
    return new;
  end if;

  select coalesce(nullif(c.display_name, ''), nullif(c.name, ''), new.church_id)
    into resolved_church_name
  from public.churches c
  where c.id = new.church_id or c."placeId" = new.church_id
  limit 1;

  update public.users
     set "placeId" = new.church_id,
         "placeName" = coalesce(resolved_church_name, new.church_id),
         "accountState" = 'active',
         roles = case
           when roles is null or cardinality(roles) = 0 then array['Member']
           else roles
         end
   where id = new.user_id or uid = new.user_id::text;

  return new;
end;
$$;

drop trigger if exists sync_active_membership_profile_trigger
  on public.church_memberships;
create trigger sync_active_membership_profile_trigger
after insert or update of membership_status
on public.church_memberships
for each row execute function public.sync_active_membership_profile();

-- Backfill any already-approved legacy profile that missed the narrow update
-- in an older approval routine.
update public.users u
   set uid = u.id::text
 where nullif(trim(coalesce(u.uid, '')), '') is null
   and u.id is not null
   and not exists (
     select 1
     from public.users collision
     where collision.id <> u.id
       and collision.uid = u.id::text
   );

update public.users u
   set "placeId" = cm.church_id,
       "placeName" = coalesce(nullif(c.display_name, ''), nullif(c.name, ''), cm.church_id),
       "accountState" = 'active'
  from public.church_memberships cm
  left join public.churches c
    on c.id = cm.church_id or c."placeId" = cm.church_id
 where (cm.user_id = u.id or u.uid = cm.user_id::text)
   and cm.membership_status = 'active'
   and (
     nullif(trim(coalesce(u."placeId", '')), '') is distinct from cm.church_id
     or coalesce(u."accountState", '') <> 'active'
   );
