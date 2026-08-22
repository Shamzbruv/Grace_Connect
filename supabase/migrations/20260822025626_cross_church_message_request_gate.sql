-- Cross-church and unconnected messaging must begin with an explicit request.
-- Same-church messaging remains direct, while Bible Nudges stay independent
-- encouragement and can no longer silently grant direct-message access.

create extension if not exists pgcrypto;
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create table if not exists public.direct_message_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  sender_church_id text,
  recipient_church_id text,
  reason text not null,
  intended_message text not null,
  status text not null default 'pending',
  response_message text,
  conversation_id uuid references public.direct_conversations(id) on delete set null,
  delivered_message_id uuid references public.direct_messages(id) on delete set null,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint direct_message_requests_no_self check (sender_id <> recipient_id),
  constraint direct_message_requests_reason_length
    check (char_length(trim(reason)) between 3 and 500),
  constraint direct_message_requests_message_length
    check (char_length(trim(intended_message)) between 1 and 4000),
  constraint direct_message_requests_response_length
    check (response_message is null or char_length(trim(response_message)) <= 500),
  constraint direct_message_requests_status
    check (status in ('pending', 'accepted', 'denied', 'cancelled')),
  constraint direct_message_requests_response_time check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  )
);

create unique index if not exists direct_message_requests_one_pending_idx
  on public.direct_message_requests (sender_id, recipient_id)
  where status = 'pending';

create index if not exists direct_message_requests_recipient_status_idx
  on public.direct_message_requests (recipient_id, status, created_at desc);

create index if not exists direct_message_requests_sender_status_idx
  on public.direct_message_requests (sender_id, status, created_at desc);

create index if not exists direct_message_requests_denial_cooldown_idx
  on public.direct_message_requests (sender_id, recipient_id, responded_at desc)
  where status = 'denied';

alter table public.direct_message_requests enable row level security;

drop policy if exists "Participants view direct message requests"
  on public.direct_message_requests;
create policy "Participants view direct message requests"
  on public.direct_message_requests
  for select
  to authenticated
  using (
    sender_id = (select auth.uid())
    or recipient_id = (select auth.uid())
  );

revoke all on table public.direct_message_requests from public, anon, authenticated;
grant select on table public.direct_message_requests to authenticated;
grant all on table public.direct_message_requests to service_role;

alter table public.direct_message_requests replica identity full;

-- Durable push intent is written in the same transaction as each request or
-- decision. Client delivery is only a fast path; cron safely retries failures
-- and app/network termination cannot lose the notification.
create table if not exists public.direct_message_request_push_deliveries (
  request_id uuid not null
    references public.direct_message_requests(id) on delete cascade,
  event text not null
    check (event in ('request', 'accepted', 'denied')),
  status text not null default 'pending'
    check (status in ('pending', 'leased', 'sent', 'failed', 'skipped')),
  attempt_count integer not null default 0
    check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (request_id, event),
  constraint direct_message_request_push_lease_shape check (
    (status = 'leased' and lease_token is not null and lease_expires_at is not null)
    or (status <> 'leased' and lease_token is null and lease_expires_at is null)
  ),
  constraint direct_message_request_push_sent_shape check (
    (status = 'sent' and sent_at is not null)
    or (status <> 'sent' and sent_at is null)
  )
);

create index if not exists direct_message_request_push_due_idx
  on public.direct_message_request_push_deliveries (
    status,
    next_attempt_at,
    created_at
  )
  where status in ('pending', 'failed', 'leased');

alter table public.direct_message_request_push_deliveries
  enable row level security;
revoke all on table public.direct_message_request_push_deliveries
  from public, anon, authenticated;
grant all on table public.direct_message_request_push_deliveries
  to service_role;

-- Bible Nudges are a separate cross-church encouragement channel, but their
-- push delivery needs the same crash/offline guarantees as message requests.
create table if not exists public.bible_nudge_push_deliveries (
  nudge_id uuid not null
    references public.bible_nudges(id) on delete cascade,
  event text not null
    check (event in ('request', 'accepted', 'declined')),
  status text not null default 'pending'
    check (status in ('pending', 'leased', 'sent', 'failed', 'skipped')),
  attempt_count integer not null default 0
    check (attempt_count between 0 and 8),
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (nudge_id, event),
  constraint bible_nudge_push_lease_shape check (
    (status = 'leased' and lease_token is not null and lease_expires_at is not null)
    or (status <> 'leased' and lease_token is null and lease_expires_at is null)
  ),
  constraint bible_nudge_push_sent_shape check (
    (status = 'sent' and sent_at is not null)
    or (status <> 'sent' and sent_at is null)
  )
);

create index if not exists bible_nudge_push_due_idx
  on public.bible_nudge_push_deliveries (
    status,
    next_attempt_at,
    created_at
  )
  where status in ('pending', 'failed', 'leased');

alter table public.bible_nudge_push_deliveries enable row level security;
revoke all on table public.bible_nudge_push_deliveries
  from public, anon, authenticated;
grant all on table public.bible_nudge_push_deliveries
  to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'direct_message_requests'
     ) then
    alter publication supabase_realtime
      add table public.direct_message_requests;
  end if;
end;
$$;

-- Resolve legacy users.uid aliases to the canonical Auth user id used by the
-- request table and by current clients.
create or replace function public.resolve_direct_message_user_id(
  candidate_user_id text
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.users u
  where u.id::text = nullif(trim(candidate_user_id), '')
     or u.uid = nullif(trim(candidate_user_id), '')
  order by (u.id::text = nullif(trim(candidate_user_id), '')) desc
  limit 1;
$$;

create or replace function public.direct_message_identity_keys(
  target_user_id uuid
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array_remove(array[target_user_id::text, nullif(u.uid, '')], null)
  from (select target_user_id) requested
  left join public.users u on u.id = requested.target_user_id;
$$;

-- RLS policies only need the signed-in user's identity aliases. Exposing a
-- no-argument wrapper avoids granting arbitrary profile-alias lookups.
create or replace function public.direct_message_viewer_identity_keys()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select public.direct_message_identity_keys((select auth.uid()));
$$;

create or replace function public.direct_message_active_church_keys(
  target_user_id uuid
)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct church_key), '{}'::text[])
  from public.church_memberships cm
  left join public.churches c
    on c.id = cm.church_id
    or c."placeId" = cm.church_id
  cross join lateral unnest(array[
    nullif(trim(cm.church_id), ''),
    nullif(trim(c.id), ''),
    nullif(trim(c."placeId"), '')
  ]::text[]) as church_key
  where cm.user_id = target_user_id
    and cm.membership_status = 'active'
    and church_key is not null;
$$;

create or replace function public.users_share_active_church(
  first_user_id uuid,
  second_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    coalesce(array_length(public.direct_message_active_church_keys(first_user_id), 1), 0) > 0
    and public.direct_message_active_church_keys(first_user_id)
      && public.direct_message_active_church_keys(second_user_id);
$$;

-- Bible Nudges are intentionally limited to members of two different active
-- churches. Visitors without an active church use a message request instead.
create or replace function public.users_have_different_active_churches(
  first_user_id uuid,
  second_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) in (first_user_id, second_user_id)
    and
    coalesce(array_length(public.direct_message_active_church_keys(first_user_id), 1), 0) > 0
    and coalesce(array_length(public.direct_message_active_church_keys(second_user_id), 1), 0) > 0
    and not public.users_share_active_church(first_user_id, second_user_id);
$$;

create or replace function public.can_send_bible_nudge(
  sender_user_id uuid,
  recipient_user_id uuid,
  sender_church_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) = sender_user_id
    and public.users_have_different_active_churches(
      sender_user_id,
      recipient_user_id
    )
    and nullif(trim(sender_church_id), '') = any(
      public.direct_message_active_church_keys(sender_user_id)
    );
$$;

-- Retire grants that were produced by the old Bible-Nudge shortcut. A Bible
-- Nudge remains visible and actionable, but accepting it is not consent to a
-- private conversation.
update public.direct_message_grants
set revoked_at = coalesce(revoked_at, now())
where source_type = 'bible_nudge'
  and revoked_at is null;

create or replace function public.has_direct_message_grant(
  first_user_id text,
  second_user_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with resolved as (
    select
      public.resolve_direct_message_user_id(first_user_id) as first_id,
      public.resolve_direct_message_user_id(second_user_id) as second_id
  )
  select exists (
    select 1
    from resolved r
    join public.direct_message_grants g
      on g.participant_key = public.direct_message_participant_key(
           r.first_id::text,
           r.second_id::text
         )
      or (
        public.resolve_direct_message_user_id(g.user_a) in (r.first_id, r.second_id)
        and public.resolve_direct_message_user_id(g.user_b) in (r.first_id, r.second_id)
        and public.resolve_direct_message_user_id(g.user_a)
          <> public.resolve_direct_message_user_id(g.user_b)
      )
    where r.first_id is not null
      and r.second_id is not null
      and (select auth.uid()) in (r.first_id, r.second_id)
      and g.revoked_at is null
      and g.source_type in ('message_request', 'manual')
  );
$$;

create or replace function public.direct_message_pair_is_blocked(
  first_user_id uuid,
  second_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_blocks b
    where (
      b.blocker_id = any(public.direct_message_identity_keys(first_user_id))
      and b.blocked_user_id = any(public.direct_message_identity_keys(second_user_id))
    ) or (
      b.blocker_id = any(public.direct_message_identity_keys(second_user_id))
      and b.blocked_user_id = any(public.direct_message_identity_keys(first_user_id))
    )
  );
$$;

create or replace function public.can_direct_message_pair(
  first_user_id text,
  second_user_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with resolved as (
    select
      public.resolve_direct_message_user_id(first_user_id) as first_id,
      public.resolve_direct_message_user_id(second_user_id) as second_id
  )
  select coalesce((
    select
      r.first_id is not null
      and r.second_id is not null
      and r.first_id <> r.second_id
      and (select auth.uid()) in (r.first_id, r.second_id)
      and not public.direct_message_pair_is_blocked(r.first_id, r.second_id)
      and (
        public.users_share_active_church(r.first_id, r.second_id)
        or public.has_direct_message_grant(r.first_id::text, r.second_id::text)
      )
    from resolved r
  ), false);
$$;

create or replace function public.can_send_direct_message_to_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.direct_conversations c
    cross join lateral (
      select public.resolve_direct_message_user_id(member_id) as member_id
      from unnest(c.member_ids) as member_id
      where public.resolve_direct_message_user_id(member_id) is not null
        and public.resolve_direct_message_user_id(member_id) <> (select auth.uid())
      limit 1
    ) peer
    where c.id = target_conversation_id
      and c.member_ids && public.direct_message_identity_keys((select auth.uid()))
      and public.can_direct_message_pair(
        (select auth.uid())::text,
        peer.member_id::text
      )
  );
$$;

revoke all on function public.resolve_direct_message_user_id(text)
  from public, anon, authenticated;
revoke all on function public.direct_message_identity_keys(uuid)
  from public, anon, authenticated;
revoke all on function public.direct_message_viewer_identity_keys()
  from public, anon, authenticated;
revoke all on function public.direct_message_active_church_keys(uuid)
  from public, anon, authenticated;
revoke all on function public.users_share_active_church(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.users_have_different_active_churches(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.can_send_bible_nudge(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.has_direct_message_grant(text, text)
  from public, anon, authenticated;
revoke all on function public.direct_message_pair_is_blocked(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.can_direct_message_pair(text, text)
  from public, anon, authenticated;
revoke all on function public.can_send_direct_message_to_conversation(uuid)
  from public, anon, authenticated;

-- RLS policies invoke these guarded helpers as authenticated callers. Each
-- helper still requires auth.uid() to be one of the pair, preventing BOLA.
grant execute on function public.has_direct_message_grant(text, text)
  to authenticated;
grant execute on function public.direct_message_viewer_identity_keys()
  to authenticated;
grant execute on function public.can_direct_message_pair(text, text)
  to authenticated;
grant execute on function public.can_send_direct_message_to_conversation(uuid)
  to authenticated;
grant execute on function public.can_send_bible_nudge(uuid, uuid, text)
  to authenticated;

-- All in-app notifications are now created by trusted database functions or
-- service-role code. Signed-in clients must not be able to forge an arbitrary
-- notification to another user through this SECURITY DEFINER function.
create or replace function public.create_notification(
  target_user_id uuid,
  actor_user_id uuid,
  notification_type text,
  notification_title text,
  notification_body text,
  notification_place_id text default null,
  notification_entity_table text default null,
  notification_entity_id text default null,
  notification_route text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inserted_id uuid;
  resolved_actor_name text := 'Someone';
begin
  if target_user_id is null then
    return null;
  end if;
  if actor_user_id is not null and target_user_id = actor_user_id then
    return null;
  end if;

  if actor_user_id is not null then
    select coalesce(
      nullif(trim(u."fullName"), ''),
      nullif(split_part(u.email, '@', 1), ''),
      'Someone'
    )
    into resolved_actor_name
    from public.users u
    where u.id = actor_user_id
    limit 1;
    resolved_actor_name := coalesce(resolved_actor_name, 'Someone');
  end if;

  insert into public.notifications (
    user_id,
    actor_id,
    actor_name,
    type,
    title,
    body,
    place_id,
    entity_table,
    entity_id,
    route
  ) values (
    target_user_id,
    actor_user_id,
    resolved_actor_name,
    notification_type,
    notification_title,
    notification_body,
    notification_place_id,
    notification_entity_table,
    notification_entity_id,
    notification_route
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

revoke all on function public.create_notification(
  uuid, uuid, text, text, text, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.create_notification(
  uuid, uuid, text, text, text, text, text, text, text
) to service_role;

create or replace function public.request_direct_message(
  recipient_user_id text,
  request_reason text,
  first_message text,
  client_request_id uuid
)
returns public.direct_message_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_id uuid := public.resolve_direct_message_user_id(recipient_user_id);
  clean_reason text := nullif(trim(coalesce(request_reason, '')), '');
  clean_message text := nullif(trim(coalesce(first_message, '')), '');
  target_profile public.users%rowtype;
  existing_request public.direct_message_requests;
  inserted_request public.direct_message_requests;
  cooldown_until timestamptz;
  sender_church text;
  recipient_church text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if target_id is null then
    raise exception 'That person could not be found';
  end if;
  if actor_id = target_id then
    raise exception 'You cannot send a message request to yourself';
  end if;
  if client_request_id is null then
    raise exception 'A request id is required';
  end if;
  if clean_reason is null or char_length(clean_reason) < 3 then
    raise exception 'Tell them why you would like to message (at least 3 characters)';
  end if;
  if char_length(clean_reason) > 500 then
    raise exception 'The request reason must be 500 characters or fewer';
  end if;
  if clean_message is null then
    raise exception 'Write the first message you want delivered if they accept';
  end if;
  if char_length(clean_message) > 4000 then
    raise exception 'The first message must be 4000 characters or fewer';
  end if;

  select * into target_profile
  from public.users u
  where u.id = target_id
  limit 1;

  if target_profile.id is null then
    raise exception 'That person could not be found';
  end if;
  if not coalesce(target_profile."allowMessages", true) then
    raise exception 'This person is not accepting message requests right now';
  end if;
  if public.direct_message_pair_is_blocked(actor_id, target_id) then
    raise exception 'Message requests are not available with this person';
  end if;
  if public.users_share_active_church(actor_id, target_id) then
    raise exception 'You are in the same church and can message this person directly';
  end if;
  if public.has_direct_message_grant(actor_id::text, target_id::text) then
    raise exception 'This person has already approved messaging. Open your inbox';
  end if;

  -- Serialize each directed pair so simultaneous devices cannot create two
  -- pending requests or bypass a denial cooldown race.
  perform pg_advisory_xact_lock(
    hashtextextended('direct-message-request:' || actor_id::text || ':' || target_id::text, 0)
  );

  select * into existing_request
  from public.direct_message_requests r
  where r.id = client_request_id
    and r.sender_id = actor_id
    and r.recipient_id = target_id
  limit 1;
  if existing_request.id is not null then
    return existing_request;
  end if;

  select * into existing_request
  from public.direct_message_requests r
  where r.sender_id = actor_id
    and r.recipient_id = target_id
    and r.status = 'pending'
  order by r.created_at desc
  limit 1;
  if existing_request.id is not null then
    return existing_request;
  end if;

  select r.responded_at + interval '30 days'
    into cooldown_until
  from public.direct_message_requests r
  where r.sender_id = actor_id
    and r.recipient_id = target_id
    and r.status = 'denied'
    and r.responded_at > now() - interval '30 days'
  order by r.responded_at desc
  limit 1;
  if cooldown_until is not null then
    raise exception using
      message = 'This person declined your request. You can send another request after ' ||
        to_char(cooldown_until at time zone 'UTC', 'YYYY-MM-DD HH24:MI UTC'),
      errcode = 'P0001',
      detail = 'MESSAGE_REQUEST_COOLDOWN';
  end if;

  select (keys)[1] into sender_church
  from (select public.direct_message_active_church_keys(actor_id) as keys) value;
  select (keys)[1] into recipient_church
  from (select public.direct_message_active_church_keys(target_id) as keys) value;

  insert into public.direct_message_requests (
    id,
    sender_id,
    recipient_id,
    sender_church_id,
    recipient_church_id,
    reason,
    intended_message
  ) values (
    client_request_id,
    actor_id,
    target_id,
    sender_church,
    recipient_church,
    clean_reason,
    clean_message
  )
  returning * into inserted_request;

  perform public.create_notification(
    target_id,
    actor_id,
    'message_request_received',
    'New message request',
    coalesce(public.display_name_for_user(actor_id), 'Someone') ||
      ' wants permission to message you.',
    sender_church,
    'direct_message_requests',
    inserted_request.id::text,
    '/inbox?tab=requests'
  );

  insert into public.direct_message_request_push_deliveries (
    request_id,
    event
  ) values (
    inserted_request.id,
    'request'
  )
  on conflict (request_id, event) do nothing;

  return inserted_request;
end;
$$;

create or replace function public.respond_to_direct_message_request(
  target_request_id uuid,
  accept_request boolean,
  response_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_request public.direct_message_requests;
  clean_response text := nullif(trim(coalesce(response_note, '')), '');
  pair_key text;
  conversation public.direct_conversations;
  initial_message public.direct_messages;
  sender_name text;
  recipient_name text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if target_request_id is null then
    raise exception 'Select a message request';
  end if;
  if clean_response is not null and char_length(clean_response) > 500 then
    raise exception 'The response must be 500 characters or fewer';
  end if;

  select * into target_request
  from public.direct_message_requests r
  where r.id = target_request_id
  for update;

  if target_request.id is null then
    raise exception 'Message request not found';
  end if;
  if target_request.recipient_id <> actor_id then
    raise exception 'Only the recipient can respond to this message request';
  end if;

  -- Safe retry: return the result of an already-completed matching decision
  -- without duplicating the conversation, first message, or notifications.
  if target_request.status = 'accepted' and accept_request then
    return jsonb_build_object(
      'request', to_jsonb(target_request),
      'conversation_id', target_request.conversation_id,
      'message_id', target_request.delivered_message_id,
      'deduplicated', true
    );
  end if;
  if target_request.status = 'denied' and not accept_request then
    return jsonb_build_object(
      'request', to_jsonb(target_request),
      'conversation_id', null,
      'message_id', null,
      'deduplicated', true
    );
  end if;
  if target_request.status <> 'pending' then
    raise exception 'This message request has already been answered';
  end if;

  select coalesce(public.display_name_for_user(target_request.sender_id), 'Someone')
    into sender_name;
  select coalesce(public.display_name_for_user(target_request.recipient_id), 'Member')
    into recipient_name;

  if not accept_request then
    update public.direct_message_requests
    set status = 'denied',
        response_message = clean_response,
        responded_at = now()
    where id = target_request.id
    returning * into target_request;

    perform public.create_notification(
      target_request.sender_id,
      actor_id,
      'message_request_denied',
      'Message request declined',
      recipient_name || ' declined your message request.' ||
        case when clean_response is null then ''
          else ' Response: ' || left(clean_response, 180)
        end || ' You can request again in 30 days.',
      target_request.recipient_church_id,
      'direct_message_requests',
      target_request.id::text,
      '/inbox?tab=requests'
    );

    update public.direct_message_request_push_deliveries
    set status = 'skipped',
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where request_id = target_request.id
      and event = 'request'
      and status <> 'sent';

    insert into public.direct_message_request_push_deliveries (
      request_id,
      event
    ) values (
      target_request.id,
      'denied'
    )
    on conflict (request_id, event) do nothing;

    return jsonb_build_object(
      'request', to_jsonb(target_request),
      'conversation_id', null,
      'message_id', null,
      'deduplicated', false
    );
  end if;

  if public.direct_message_pair_is_blocked(
    target_request.sender_id,
    target_request.recipient_id
  ) then
    raise exception 'Messages are not available with this person';
  end if;

  pair_key := public.direct_message_participant_key(
    target_request.sender_id::text,
    target_request.recipient_id::text
  );

  insert into public.direct_message_grants (
    participant_key,
    user_a,
    user_b,
    source_type,
    source_id,
    granted_by,
    created_at,
    revoked_at
  ) values (
    pair_key,
    least(target_request.sender_id::text, target_request.recipient_id::text),
    greatest(target_request.sender_id::text, target_request.recipient_id::text),
    'message_request',
    target_request.id,
    actor_id::text,
    now(),
    null
  )
  on conflict (participant_key) do update
    set source_type = 'message_request',
        source_id = excluded.source_id,
        granted_by = excluded.granted_by,
        revoked_at = null;

  select * into conversation
  from public.direct_conversations c
  where c.participant_key = pair_key
     or (
       c.member_ids && public.direct_message_identity_keys(target_request.sender_id)
       and c.member_ids && public.direct_message_identity_keys(target_request.recipient_id)
     )
  order by c.created_at desc
  limit 1;

  if conversation.id is null then
    insert into public.direct_conversations (
      church_id,
      member_ids,
      participant_key,
      created_by,
      last_message_at,
      hidden_for
    ) values (
      coalesce(
        nullif(target_request.sender_church_id, ''),
        nullif(target_request.recipient_church_id, ''),
        'public'
      ),
      array[target_request.sender_id::text, target_request.recipient_id::text],
      pair_key,
      target_request.sender_id::text,
      now(),
      '{}'::text[]
    )
    returning * into conversation;
  else
    update public.direct_conversations
    set hidden_for = array(
          select hidden_id
          from unnest(coalesce(hidden_for, '{}'::text[])) as hidden_id
          where not hidden_id = any(
            public.direct_message_identity_keys(target_request.sender_id)
          )
            and not hidden_id = any(
              public.direct_message_identity_keys(target_request.recipient_id)
            )
        )
    where id = conversation.id
    returning * into conversation;
  end if;

  insert into public.direct_messages (
    id,
    conversation_id,
    sender_id,
    text,
    media_type,
    created_at,
    expires_at
  ) values (
    gen_random_uuid(),
    conversation.id,
    target_request.sender_id::text,
    target_request.intended_message,
    'text',
    now(),
    now() + interval '30 days'
  )
  returning * into initial_message;

  update public.direct_conversations
  set last_message = left(target_request.intended_message, 500),
      last_sender_id = target_request.sender_id::text,
      last_message_at = initial_message.created_at,
      hidden_for = '{}'::text[]
  where id = conversation.id
  returning * into conversation;

  update public.direct_message_requests
  set status = 'accepted',
      response_message = clean_response,
      conversation_id = conversation.id,
      delivered_message_id = initial_message.id,
      responded_at = now()
  where id = target_request.id
  returning * into target_request;

  perform public.create_notification(
    target_request.sender_id,
    actor_id,
    'message_request_accepted',
    'Message request accepted',
    recipient_name || ' accepted your message request. Your first message was delivered.' ||
      case when clean_response is null then ''
        else ' Response: ' || left(clean_response, 180)
      end,
    target_request.recipient_church_id,
    'direct_message_requests',
    target_request.id::text,
    '/inbox?tab=messages'
  );

  update public.direct_message_request_push_deliveries
  set status = 'skipped',
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  where request_id = target_request.id
    and event = 'request'
    and status <> 'sent';

  insert into public.direct_message_request_push_deliveries (
    request_id,
    event
  ) values (
    target_request.id,
    'accepted'
  )
  on conflict (request_id, event) do nothing;

  return jsonb_build_object(
    'request', to_jsonb(target_request),
    'conversation_id', conversation.id,
    'message_id', initial_message.id,
    'deduplicated', false
  );
end;
$$;

create or replace function public.cancel_direct_message_request(
  target_request_id uuid
)
returns public.direct_message_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  cancelled_request public.direct_message_requests;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  update public.direct_message_requests
  set status = 'cancelled',
      responded_at = now()
  where id = target_request_id
    and sender_id = actor_id
    and status = 'pending'
  returning * into cancelled_request;

  if cancelled_request.id is null then
    raise exception 'Pending message request not found';
  end if;

  update public.notifications
  set is_read = true
  where user_id = cancelled_request.recipient_id
    and entity_table = 'direct_message_requests'
    and entity_id = cancelled_request.id::text
    and type = 'message_request_received';

  update public.direct_message_request_push_deliveries
  set status = 'skipped',
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  where request_id = cancelled_request.id
    and event = 'request'
    and status <> 'sent';

  return cancelled_request;
end;
$$;

revoke all on function public.request_direct_message(text, text, text, uuid)
  from public, anon;
revoke all on function public.respond_to_direct_message_request(uuid, boolean, text)
  from public, anon;
revoke all on function public.cancel_direct_message_request(uuid)
  from public, anon;
grant execute on function public.request_direct_message(text, text, text, uuid)
  to authenticated;
grant execute on function public.respond_to_direct_message_request(uuid, boolean, text)
  to authenticated;
grant execute on function public.cancel_direct_message_request(uuid)
  to authenticated;

-- Service-role lease functions coordinate the immediate client-triggered
-- attempt and the cron retry worker. At most one worker owns an event at a
-- time; the shared FCM outbox remains the final provider idempotency guard.
create or replace function public.claim_message_request_push_delivery(
  p_request_id uuid,
  p_event text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery public.direct_message_request_push_deliveries;
  request_status text;
  new_lease_token uuid;
begin
  if p_request_id is null
     or p_event not in ('request', 'accepted', 'denied') then
    raise exception 'A valid message-request delivery is required';
  end if;

  select d.* into delivery
  from public.direct_message_request_push_deliveries d
  where d.request_id = p_request_id
    and d.event = p_event
  for update;

  if delivery.request_id is null then
    return jsonb_build_object('claimed', false, 'status', 'missing');
  end if;
  if delivery.status = 'sent' then
    return jsonb_build_object('claimed', false, 'status', 'sent');
  end if;
  if delivery.status = 'skipped' then
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;
  if delivery.attempt_count >= 8
     or delivery.created_at < now() - interval '7 days' then
    update public.direct_message_request_push_deliveries
    set status = 'skipped',
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where request_id = p_request_id
      and event = p_event;
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;
  if delivery.status = 'leased' and delivery.lease_expires_at > now() then
    return jsonb_build_object('claimed', false, 'status', 'leased');
  end if;
  if delivery.next_attempt_at > now() then
    return jsonb_build_object('claimed', false, 'status', delivery.status);
  end if;

  select r.status into request_status
  from public.direct_message_requests r
  where r.id = p_request_id;
  if request_status is null
     or (p_event = 'request' and request_status <> 'pending')
     or (p_event = 'accepted' and request_status <> 'accepted')
     or (p_event = 'denied' and request_status <> 'denied') then
    update public.direct_message_request_push_deliveries
    set status = 'skipped',
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where request_id = p_request_id
      and event = p_event;
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;

  new_lease_token := gen_random_uuid();
  update public.direct_message_request_push_deliveries
  set status = 'leased',
      attempt_count = attempt_count + 1,
      lease_token = new_lease_token,
      lease_expires_at = now() + interval '2 minutes',
      updated_at = now()
  where request_id = p_request_id
    and event = p_event;

  return jsonb_build_object(
    'claimed', true,
    'status', 'leased',
    'request_id', p_request_id,
    'event', p_event,
    'lease_token', new_lease_token
  );
end;
$$;

create or replace function public.claim_due_message_request_push_deliveries(
  p_limit integer default 50
)
returns table (
  request_id uuid,
  event text,
  lease_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.direct_message_request_push_deliveries d
  set status = 'skipped',
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  from public.direct_message_requests r
  where r.id = d.request_id
    and d.status in ('pending', 'failed', 'leased')
    and (
      d.created_at < now() - interval '7 days'
      or d.attempt_count >= 8
      or (d.event = 'request' and r.status <> 'pending')
      or (d.event = 'accepted' and r.status <> 'accepted')
      or (d.event = 'denied' and r.status <> 'denied')
    );

  return query
  with candidates as materialized (
    select d.request_id, d.event
    from public.direct_message_request_push_deliveries d
    join public.direct_message_requests r on r.id = d.request_id
    where d.attempt_count < 8
      and d.created_at >= now() - interval '7 days'
      and d.next_attempt_at <= now()
      and (
        d.status in ('pending', 'failed')
        or (d.status = 'leased' and d.lease_expires_at <= now())
      )
      and (
        (d.event = 'request' and r.status = 'pending')
        or (d.event = 'accepted' and r.status = 'accepted')
        or (d.event = 'denied' and r.status = 'denied')
      )
    order by d.next_attempt_at, d.created_at
    for update of d skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  )
  update public.direct_message_request_push_deliveries d
  set status = 'leased',
      attempt_count = d.attempt_count + 1,
      lease_token = gen_random_uuid(),
      lease_expires_at = now() + interval '2 minutes',
      updated_at = now()
  from candidates c
  where d.request_id = c.request_id
    and d.event = c.event
  returning d.request_id, d.event, d.lease_token;
end;
$$;

create or replace function public.complete_message_request_push_delivery(
  p_request_id uuid,
  p_event text,
  p_lease_token uuid,
  p_sent boolean,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_count integer;
begin
  update public.direct_message_request_push_deliveries d
  set status = case when coalesce(p_sent, false) then 'sent' else 'failed' end,
      sent_at = case when coalesce(p_sent, false) then now() else null end,
      next_attempt_at = case
        when coalesce(p_sent, false) then now()
        else now() + make_interval(
          mins => least(60, (power(2, greatest(0, d.attempt_count - 1)))::integer)
        )
      end,
      lease_token = null,
      lease_expires_at = null,
      last_error = case
        when coalesce(p_sent, false) then null
        else left(coalesce(nullif(trim(p_error), ''), 'Push delivery failed'), 500)
      end,
      updated_at = now()
  where d.request_id = p_request_id
    and d.event = p_event
    and d.status = 'leased'
    and d.lease_token = p_lease_token;
  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.claim_message_request_push_delivery(uuid, text)
  from public, anon, authenticated;
revoke all on function public.claim_due_message_request_push_deliveries(integer)
  from public, anon, authenticated;
revoke all on function public.complete_message_request_push_delivery(
  uuid, text, uuid, boolean, text
) from public, anon, authenticated;
grant execute on function public.claim_message_request_push_delivery(uuid, text)
  to service_role;
grant execute on function public.claim_due_message_request_push_deliveries(integer)
  to service_role;
grant execute on function public.complete_message_request_push_delivery(
  uuid, text, uuid, boolean, text
) to service_role;

create or replace function public.claim_bible_nudge_push_delivery(
  p_nudge_id uuid,
  p_event text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery public.bible_nudge_push_deliveries;
  nudge_status text;
  new_lease_token uuid;
begin
  if p_nudge_id is null
     or p_event not in ('request', 'accepted', 'declined') then
    raise exception 'A valid Bible-Nudge delivery is required';
  end if;

  select d.* into delivery
  from public.bible_nudge_push_deliveries d
  where d.nudge_id = p_nudge_id
    and d.event = p_event
  for update;

  if delivery.nudge_id is null then
    return jsonb_build_object('claimed', false, 'status', 'missing');
  end if;
  if delivery.status = 'sent' then
    return jsonb_build_object('claimed', false, 'status', 'sent');
  end if;
  if delivery.status = 'skipped' then
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;
  if delivery.attempt_count >= 8
     or delivery.created_at < now() - interval '7 days' then
    update public.bible_nudge_push_deliveries
    set status = 'skipped',
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where nudge_id = p_nudge_id
      and event = p_event;
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;
  if delivery.status = 'leased' and delivery.lease_expires_at > now() then
    return jsonb_build_object('claimed', false, 'status', 'leased');
  end if;
  if delivery.next_attempt_at > now() then
    return jsonb_build_object('claimed', false, 'status', delivery.status);
  end if;

  select n.status into nudge_status
  from public.bible_nudges n
  where n.id = p_nudge_id;
  if nudge_status is null
     or (p_event = 'request' and nudge_status <> 'pending')
     or (p_event = 'accepted' and nudge_status <> 'accepted')
     or (p_event = 'declined' and nudge_status <> 'declined') then
    update public.bible_nudge_push_deliveries
    set status = 'skipped',
        lease_token = null,
        lease_expires_at = null,
        updated_at = now()
    where nudge_id = p_nudge_id
      and event = p_event;
    return jsonb_build_object('claimed', false, 'status', 'skipped');
  end if;

  new_lease_token := gen_random_uuid();
  update public.bible_nudge_push_deliveries
  set status = 'leased',
      attempt_count = attempt_count + 1,
      lease_token = new_lease_token,
      lease_expires_at = now() + interval '2 minutes',
      updated_at = now()
  where nudge_id = p_nudge_id
    and event = p_event;

  return jsonb_build_object(
    'claimed', true,
    'status', 'leased',
    'nudge_id', p_nudge_id,
    'event', p_event,
    'lease_token', new_lease_token
  );
end;
$$;

create or replace function public.claim_due_bible_nudge_push_deliveries(
  p_limit integer default 50
)
returns table (
  nudge_id uuid,
  event text,
  lease_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.bible_nudge_push_deliveries d
  set status = 'skipped',
      lease_token = null,
      lease_expires_at = null,
      updated_at = now()
  from public.bible_nudges n
  where n.id = d.nudge_id
    and d.status in ('pending', 'failed', 'leased')
    and (
      d.created_at < now() - interval '7 days'
      or d.attempt_count >= 8
      or (d.event = 'request' and n.status <> 'pending')
      or (d.event = 'accepted' and n.status <> 'accepted')
      or (d.event = 'declined' and n.status <> 'declined')
    );

  return query
  with candidates as materialized (
    select d.nudge_id, d.event
    from public.bible_nudge_push_deliveries d
    join public.bible_nudges n on n.id = d.nudge_id
    where d.attempt_count < 8
      and d.created_at >= now() - interval '7 days'
      and d.next_attempt_at <= now()
      and (
        d.status in ('pending', 'failed')
        or (d.status = 'leased' and d.lease_expires_at <= now())
      )
      and (
        (d.event = 'request' and n.status = 'pending')
        or (d.event = 'accepted' and n.status = 'accepted')
        or (d.event = 'declined' and n.status = 'declined')
      )
    order by d.next_attempt_at, d.created_at
    for update of d skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  )
  update public.bible_nudge_push_deliveries d
  set status = 'leased',
      attempt_count = d.attempt_count + 1,
      lease_token = gen_random_uuid(),
      lease_expires_at = now() + interval '2 minutes',
      updated_at = now()
  from candidates c
  where d.nudge_id = c.nudge_id
    and d.event = c.event
  returning d.nudge_id, d.event, d.lease_token;
end;
$$;

create or replace function public.complete_bible_nudge_push_delivery(
  p_nudge_id uuid,
  p_event text,
  p_lease_token uuid,
  p_sent boolean,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_count integer;
begin
  update public.bible_nudge_push_deliveries d
  set status = case when coalesce(p_sent, false) then 'sent' else 'failed' end,
      sent_at = case when coalesce(p_sent, false) then now() else null end,
      next_attempt_at = case
        when coalesce(p_sent, false) then now()
        else now() + make_interval(
          mins => least(60, (power(2, greatest(0, d.attempt_count - 1)))::integer)
        )
      end,
      lease_token = null,
      lease_expires_at = null,
      last_error = case
        when coalesce(p_sent, false) then null
        else left(coalesce(nullif(trim(p_error), ''), 'Push delivery failed'), 500)
      end,
      updated_at = now()
  where d.nudge_id = p_nudge_id
    and d.event = p_event
    and d.status = 'leased'
    and d.lease_token = p_lease_token;
  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.claim_bible_nudge_push_delivery(uuid, text)
  from public, anon, authenticated;
revoke all on function public.claim_due_bible_nudge_push_deliveries(integer)
  from public, anon, authenticated;
revoke all on function public.complete_bible_nudge_push_delivery(
  uuid, text, uuid, boolean, text
) from public, anon, authenticated;
grant execute on function public.claim_bible_nudge_push_delivery(uuid, text)
  to service_role;
grant execute on function public.claim_due_bible_nudge_push_deliveries(integer)
  to service_role;
grant execute on function public.complete_bible_nudge_push_delivery(
  uuid, text, uuid, boolean, text
) to service_role;

-- The sole conversation-creation RPC now enforces same-active-church or an
-- accepted message request before it even returns an existing conversation.
create or replace function public.get_or_create_direct_conversation(
  other_user_id text
)
returns public.direct_conversations
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_id uuid := public.resolve_direct_message_user_id(other_user_id);
  target_profile public.users%rowtype;
  pair_key text;
  existing_conversation public.direct_conversations;
  new_conversation public.direct_conversations;
  conversation_church_id text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if target_id is null then
    raise exception 'That person could not be found';
  end if;
  if actor_id = target_id then
    raise exception 'You cannot message yourself';
  end if;
  if public.direct_message_pair_is_blocked(actor_id, target_id) then
    raise exception 'Messages are not available with this person';
  end if;

  select * into target_profile
  from public.users u
  where u.id = target_id
  limit 1;

  if not public.can_direct_message_pair(actor_id::text, target_id::text) then
    if not coalesce(target_profile."allowMessages", true) then
      raise exception 'This person is not accepting message requests right now';
    end if;
    raise exception using
      message = 'A message request is required before you can message this person',
      errcode = 'P0001',
      detail = 'MESSAGE_REQUEST_REQUIRED';
  end if;

  pair_key := public.direct_message_participant_key(
    actor_id::text,
    target_id::text
  );

  select * into existing_conversation
  from public.direct_conversations c
  where c.participant_key = pair_key
     or (
       c.member_ids && public.direct_message_identity_keys(actor_id)
       and c.member_ids && public.direct_message_identity_keys(target_id)
     )
  order by c.created_at desc
  limit 1;

  if existing_conversation.id is not null then
    update public.direct_conversations
    set hidden_for = array(
          select hidden_id
          from unnest(coalesce(hidden_for, '{}'::text[])) as hidden_id
          where not hidden_id = any(public.direct_message_identity_keys(actor_id))
            and not hidden_id = any(public.direct_message_identity_keys(target_id))
        )
    where id = existing_conversation.id
    returning * into existing_conversation;
    return existing_conversation;
  end if;

  select (keys)[1] into conversation_church_id
  from (select public.direct_message_active_church_keys(actor_id) as keys) value;
  if conversation_church_id is null then
    select (keys)[1] into conversation_church_id
    from (select public.direct_message_active_church_keys(target_id) as keys) value;
  end if;

  insert into public.direct_conversations (
    church_id,
    member_ids,
    participant_key,
    created_by,
    last_message_at
  ) values (
    coalesce(conversation_church_id, 'public'),
    array[actor_id::text, target_id::text],
    pair_key,
    actor_id::text,
    now()
  )
  returning * into new_conversation;

  return new_conversation;
end;
$$;

revoke all on function public.get_or_create_direct_conversation(text)
  from public, anon;
grant execute on function public.get_or_create_direct_conversation(text)
  to authenticated;

-- Client-side table writes cannot create a conversation around the RPC.
drop policy if exists "Members create direct conversations"
  on public.direct_conversations;
revoke insert, delete on table public.direct_conversations from authenticated;
grant select, update on table public.direct_conversations to authenticated;

drop policy if exists "Members view own direct conversations"
  on public.direct_conversations;
create policy "Members view own direct conversations"
  on public.direct_conversations
  for select
  to authenticated
  using (
    member_ids && public.direct_message_viewer_identity_keys()
  );

drop policy if exists "Members update own direct conversations"
  on public.direct_conversations;
create policy "Members update own direct conversations"
  on public.direct_conversations
  for update
  to authenticated
  using (
    member_ids && public.direct_message_viewer_identity_keys()
  )
  with check (
    member_ids && public.direct_message_viewer_identity_keys()
  );

drop policy if exists "Members view own direct messages"
  on public.direct_messages;
create policy "Members view own direct messages"
  on public.direct_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and c.member_ids
          && public.direct_message_viewer_identity_keys()
    )
  );

drop policy if exists "Members send own direct messages"
  on public.direct_messages;
create policy "Members send own direct messages"
  on public.direct_messages
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())::text
    and (
      nullif(trim(coalesce(text, '')), '') is not null
      or nullif(trim(coalesce(media_url, '')), '') is not null
    )
    and public.can_send_direct_message_to_conversation(conversation_id)
  );

drop policy if exists "Members mark own direct messages read"
  on public.direct_messages;
create policy "Members mark own direct messages read"
  on public.direct_messages
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and c.member_ids
          && public.direct_message_viewer_identity_keys()
    )
  )
  with check (
    exists (
      select 1
      from public.direct_conversations c
      where c.id = conversation_id
        and c.member_ids
          && public.direct_message_viewer_identity_keys()
    )
  );

drop policy if exists "Members delete own direct messages"
  on public.direct_messages;
create policy "Members delete own direct messages"
  on public.direct_messages
  for delete
  to authenticated
  using (
    sender_id = any(public.direct_message_viewer_identity_keys())
  );

revoke all on table public.direct_messages from anon;
grant select, insert, update, delete on table public.direct_messages to authenticated;

-- Resolve both canonical Auth UUIDs and historical users.uid aliases before
-- notifying the peer. This guarantees that accepting a request delivers one
-- unread first message to the accepting recipient even for legacy chats.
create or replace function public.notify_on_direct_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  sender_uuid uuid := public.resolve_direct_message_user_id(new.sender_id);
  target_uuid uuid;
  target_church text;
begin
  select public.resolve_direct_message_user_id(member_id)
    into target_uuid
  from public.direct_conversations c
  cross join lateral unnest(c.member_ids) as member_id
  where c.id = new.conversation_id
    and public.resolve_direct_message_user_id(member_id) is not null
    and public.resolve_direct_message_user_id(member_id) <> sender_uuid
  limit 1;

  select c.church_id
    into target_church
  from public.direct_conversations c
  where c.id = new.conversation_id;

  if sender_uuid is not null and target_uuid is not null then
    perform public.create_notification(
      target_uuid,
      sender_uuid,
      'direct_message',
      'New message',
      coalesce(public.display_name_for_user(sender_uuid), 'Someone')
        || ' sent you a message.',
      target_church,
      'direct_messages',
      new.id::text,
      '/inbox'
    );
  end if;

  return new;
end;
$$;

revoke all on function public.notify_on_direct_message()
  from public, anon, authenticated;

create or replace function public.protect_direct_conversation_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.church_id is distinct from old.church_id
     or new.member_ids is distinct from old.member_ids
     or new.participant_key is distinct from old.participant_key
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Conversation participants cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_direct_conversation_identity_trigger
  on public.direct_conversations;
create trigger protect_direct_conversation_identity_trigger
  before update on public.direct_conversations
  for each row execute function public.protect_direct_conversation_identity();

create or replace function public.protect_direct_message_identity()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.conversation_id is distinct from old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.text is distinct from old.text
     or new.media_url is distinct from old.media_url
     or new.media_path is distinct from old.media_path
     or new.media_type is distinct from old.media_type
     or new.duration_seconds is distinct from old.duration_seconds
     or new.reply_context is distinct from old.reply_context
     or new.created_at is distinct from old.created_at
     or new.expires_at is distinct from old.expires_at then
    raise exception 'Message content cannot be changed after sending';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_direct_message_identity_trigger
  on public.direct_messages;
create trigger protect_direct_message_identity_trigger
  before update on public.direct_messages
  for each row execute function public.protect_direct_message_identity();

-- Bible Nudge acceptance remains a supported legacy RPC name for released
-- clients, but it now accepts the nudge only. It never creates a messaging
-- grant or conversation.
create or replace function public.accept_bible_nudge_and_grant_messages(
  target_nudge_id uuid
)
returns public.direct_conversations
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_nudge public.bible_nudges;
  existing_conversation public.direct_conversations;
  pair_key text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select * into target_nudge
  from public.bible_nudges n
  where n.id = target_nudge_id
  for update;

  if target_nudge.id is null then
    raise exception 'Bible Nudge was not found';
  end if;
  if target_nudge.recipient_id <> actor_id then
    if target_nudge.status = 'accepted'
       and target_nudge.sender_id = actor_id then
      return null;
    end if;
    raise exception 'Only the recipient can accept this Bible Nudge';
  end if;
  if target_nudge.status = 'pending' then
    update public.bible_nudges
    set status = 'accepted', responded_at = now()
    where id = target_nudge.id
    returning * into target_nudge;
  elsif target_nudge.status <> 'accepted' then
    raise exception 'This Bible Nudge has already been answered';
  end if;

  pair_key := public.direct_message_participant_key(
    target_nudge.sender_id::text,
    target_nudge.recipient_id::text
  );
  select * into existing_conversation
  from public.direct_conversations c
  where c.participant_key = pair_key
    and public.can_direct_message_pair(
      target_nudge.sender_id::text,
      target_nudge.recipient_id::text
    )
  limit 1;
  return existing_conversation;
end;
$$;

revoke all on function public.accept_bible_nudge_and_grant_messages(uuid)
  from public, anon;
grant execute on function public.accept_bible_nudge_and_grant_messages(uuid)
  to authenticated;

drop policy if exists "Members create Bible Nudges" on public.bible_nudges;
create policy "Members create Bible Nudges"
  on public.bible_nudges
  for insert
  to authenticated
  with check (
    sender_id = (select auth.uid())
    and recipient_id <> (select auth.uid())
    and public.can_send_bible_nudge(sender_id, recipient_id, church_id)
  );

create or replace function public.protect_bible_nudge_response()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.sender_id is distinct from old.sender_id
     or new.sender_name is distinct from old.sender_name
     or new.recipient_id is distinct from old.recipient_id
     or new.recipient_name is distinct from old.recipient_name
     or new.church_id is distinct from old.church_id
     or new.message is distinct from old.message
     or new.created_at is distinct from old.created_at then
    raise exception 'Bible Nudge participants and message cannot be changed';
  end if;

  if old.status <> 'pending' and new.status is distinct from old.status then
    raise exception 'This Bible Nudge has already been answered';
  end if;
  if new.status is distinct from old.status then
    if (select auth.uid()) = old.recipient_id
       and new.status not in ('accepted', 'declined') then
      raise exception 'Recipients can only accept or decline a Bible Nudge';
    elsif (select auth.uid()) = old.sender_id
       and new.status <> 'cancelled' then
      raise exception 'Senders can only cancel a Bible Nudge';
    elsif (select auth.uid()) not in (old.sender_id, old.recipient_id) then
      raise exception 'Only participants can respond to a Bible Nudge';
    end if;
    if new.responded_at is null then
      new.responded_at := now();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_bible_nudge_response_trigger
  on public.bible_nudges;
create trigger protect_bible_nudge_response_trigger
  before update on public.bible_nudges
  for each row execute function public.protect_bible_nudge_response();

-- Bible-Nudge in-app notifications are transactional and idempotent on the
-- insert/status transition. The app no longer performs a forgeable best-effort
-- create_notification RPC after the database change has already committed.
create or replace function public.notify_bible_nudge_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.create_notification(
      new.recipient_id,
      new.sender_id,
      'bible_nudge_request',
      'Bible Nudge',
      coalesce(nullif(trim(new.sender_name), ''), 'Someone') ||
        ' wants to encourage you in Scripture.',
      new.church_id,
      'bible_nudges',
      new.id::text,
      '/notifications'
    );

    insert into public.bible_nudge_push_deliveries (
      nudge_id,
      event,
      status,
      next_attempt_at
    ) values (
      new.id,
      'request',
      'pending',
      now()
    )
    on conflict (nudge_id, event) do nothing;
  elsif old.status is distinct from new.status
        and new.status in ('accepted', 'declined') then
    perform public.create_notification(
      new.sender_id,
      new.recipient_id,
      'bible_nudge_response',
      case when new.status = 'accepted'
        then 'Bible Nudge accepted'
        else 'Bible Nudge declined'
      end,
      coalesce(nullif(trim(new.recipient_name), ''), 'Member') ||
        case when new.status = 'accepted'
          then ' accepted your Bible Nudge. Keep encouraging one another in Scripture.'
          else ' declined the Bible Nudge.'
        end,
      new.church_id,
      'bible_nudges',
      new.id::text,
      case when new.status = 'accepted'
        then '/public_profile?id=' || new.recipient_id::text
        else '/notifications'
      end
    );

    insert into public.bible_nudge_push_deliveries (
      nudge_id,
      event,
      status,
      next_attempt_at
    ) values (
      new.id,
      new.status,
      'pending',
      now()
    )
    on conflict (nudge_id, event) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function public.notify_bible_nudge_lifecycle()
  from public, anon, authenticated;

drop trigger if exists notify_bible_nudge_created_trigger
  on public.bible_nudges;
create trigger notify_bible_nudge_created_trigger
  after insert on public.bible_nudges
  for each row execute function public.notify_bible_nudge_lifecycle();

drop trigger if exists notify_bible_nudge_response_trigger
  on public.bible_nudges;
create trigger notify_bible_nudge_response_trigger
  after update of status on public.bible_nudges
  for each row execute function public.notify_bible_nudge_lifecycle();

comment on table public.direct_message_requests is
  'Consent gate for cross-church and unconnected direct messages. Acceptance atomically grants messaging and delivers the intended first message.';

comment on table public.direct_message_request_push_deliveries is
  'Durable, bounded push-delivery queue for direct-message request lifecycle events.';

comment on table public.bible_nudge_push_deliveries is
  'Durable, bounded push-delivery queue for Bible-Nudge lifecycle events.';

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'message-request-push-delivery-retry'
  ) then
    perform cron.unschedule('message-request-push-delivery-retry');
  end if;
end;
$$;

select cron.schedule(
  'message-request-push-delivery-retry',
  '*/2 * * * *',
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
    ) || '/functions/v1/retry-message-request-pushes',
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
