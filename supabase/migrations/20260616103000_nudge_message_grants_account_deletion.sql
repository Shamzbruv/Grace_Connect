-- Permanent Bible Nudge message access and real account deletion requests.

create extension if not exists pgcrypto;

create table if not exists public.direct_message_grants (
  id uuid primary key default gen_random_uuid(),
  participant_key text not null unique,
  user_a text not null,
  user_b text not null,
  source_type text not null default 'manual',
  source_id uuid,
  granted_by text,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint direct_message_grants_two_people check (user_a <> user_b)
);

create index if not exists direct_message_grants_user_a_idx
  on public.direct_message_grants (user_a)
  where revoked_at is null;

create index if not exists direct_message_grants_user_b_idx
  on public.direct_message_grants (user_b)
  where revoked_at is null;

alter table public.direct_message_grants enable row level security;

drop policy if exists "Participants view direct message grants"
  on public.direct_message_grants;
create policy "Participants view direct message grants"
  on public.direct_message_grants
  for select
  to authenticated
  using (
    auth.uid()::text in (user_a, user_b)
  );

create or replace function public.direct_message_participant_key(
  first_user_id text,
  second_user_id text
)
returns text
language sql
immutable
as $$
  select string_agg(value, ':' order by value)
  from unnest(array[trim(first_user_id), trim(second_user_id)]) as value
  where value is not null and value <> '';
$$;

create or replace function public.has_direct_message_grant(
  first_user_id text,
  second_user_id text
)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.direct_message_grants g
    where g.participant_key =
      public.direct_message_participant_key(first_user_id, second_user_id)
      and g.revoked_at is null
  );
$$;

grant execute on function public.has_direct_message_grant(text, text)
  to authenticated;

insert into public.direct_message_grants (
  participant_key,
  user_a,
  user_b,
  source_type,
  source_id,
  granted_by,
  created_at
)
select
  public.direct_message_participant_key(sender_id::text, recipient_id::text),
  least(sender_id::text, recipient_id::text),
  greatest(sender_id::text, recipient_id::text),
  'bible_nudge',
  id,
  recipient_id::text,
  coalesce(responded_at, created_at, now())
from public.bible_nudges
where status = 'accepted'
on conflict (participant_key) do update
  set revoked_at = null,
      source_type = excluded.source_type,
      source_id = coalesce(public.direct_message_grants.source_id, excluded.source_id),
      granted_by = coalesce(public.direct_message_grants.granted_by, excluded.granted_by);

create or replace function public.get_or_create_direct_conversation(
  other_user_id text
)
returns public.direct_conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  clean_other_user_id text := nullif(trim(other_user_id), '');
  actor_church_id text := public.get_church_id();
  conversation_key text;
  existing_conversation public.direct_conversations;
  new_conversation public.direct_conversations;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  if clean_other_user_id is null then
    raise exception 'Select a member to message';
  end if;

  if clean_other_user_id = actor_uid then
    raise exception 'You cannot message yourself';
  end if;

  if actor_church_id is null or actor_church_id = '' then
    raise exception 'Join a church before starting messages';
  end if;

  if not exists (
    select 1
    from public.users u
    where u.uid = clean_other_user_id
      and (
        coalesce(u."allowMessages", true)
        or public.has_direct_message_grant(actor_uid, clean_other_user_id)
      )
  ) then
    raise exception 'This member is not accepting messages right now';
  end if;

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = actor_uid and b.blocked_user_id = clean_other_user_id)
       or (b.blocker_id = clean_other_user_id and b.blocked_user_id = actor_uid)
  ) then
    raise exception 'Messages are not available with this member';
  end if;

  conversation_key := public.direct_message_participant_key(
    actor_uid,
    clean_other_user_id
  );

  select *
    into existing_conversation
    from public.direct_conversations
    where participant_key = conversation_key
    limit 1;

  if existing_conversation.id is not null then
    update public.direct_conversations
      set hidden_for = array_remove(
        array_remove(coalesce(hidden_for, '{}'::text[]), actor_uid),
        clean_other_user_id
      )
      where id = existing_conversation.id
      returning * into existing_conversation;

    return existing_conversation;
  end if;

  insert into public.direct_conversations (
    church_id,
    member_ids,
    participant_key,
    created_by,
    last_message_at
  )
  values (
    actor_church_id,
    array[actor_uid, clean_other_user_id],
    conversation_key,
    actor_uid,
    now()
  )
  returning * into new_conversation;

  return new_conversation;
end;
$$;

grant execute on function public.get_or_create_direct_conversation(text)
  to authenticated;

create or replace function public.accept_bible_nudge_and_grant_messages(
  target_nudge_id uuid
)
returns public.direct_conversations
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  target_nudge public.bible_nudges;
  other_user_id text;
  pair_key text;
  conversation public.direct_conversations;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  select *
    into target_nudge
    from public.bible_nudges
    where id = target_nudge_id
      and (sender_id::text = actor_uid or recipient_id::text = actor_uid)
    limit 1;

  if target_nudge.id is null then
    raise exception 'Bible Nudge was not found';
  end if;

  if target_nudge.status <> 'accepted' and target_nudge.recipient_id::text <> actor_uid then
    raise exception 'Only the recipient can accept this Bible Nudge';
  end if;

  if target_nudge.status <> 'accepted' then
    update public.bible_nudges
      set status = 'accepted',
          responded_at = now()
      where id = target_nudge.id
      returning * into target_nudge;
  end if;

  other_user_id := case
    when target_nudge.sender_id::text = actor_uid
      then target_nudge.recipient_id::text
    else target_nudge.sender_id::text
  end;

  pair_key := public.direct_message_participant_key(
    target_nudge.sender_id::text,
    target_nudge.recipient_id::text
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
  )
  values (
    pair_key,
    least(target_nudge.sender_id::text, target_nudge.recipient_id::text),
    greatest(target_nudge.sender_id::text, target_nudge.recipient_id::text),
    'bible_nudge',
    target_nudge.id,
    target_nudge.recipient_id::text,
    coalesce(target_nudge.responded_at, now()),
    null
  )
  on conflict (participant_key) do update
    set revoked_at = null,
        source_type = 'bible_nudge',
        source_id = target_nudge.id,
        granted_by = target_nudge.recipient_id::text;

  conversation := public.get_or_create_direct_conversation(other_user_id);
  return conversation;
end;
$$;

grant execute on function public.accept_bible_nudge_and_grant_messages(uuid)
  to authenticated;

create or replace function public.get_direct_conversation_peer(
  target_conversation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uid text := auth.uid()::text;
  peer_uid text;
  result jsonb;
begin
  if actor_uid is null or actor_uid = '' then
    raise exception 'Not authenticated';
  end if;

  select member_id
    into peer_uid
    from public.direct_conversations c,
      unnest(c.member_ids) as member_id
    where c.id = target_conversation_id
      and actor_uid = any(c.member_ids)
      and member_id <> actor_uid
    limit 1;

  if peer_uid is null or peer_uid = '' then
    return null;
  end if;

  select to_jsonb(u)
    into result
    from public.users u
    where u.uid = peer_uid
       or u.id::text = peer_uid
    limit 1;

  return result;
end;
$$;

grant execute on function public.get_direct_conversation_peer(uuid)
  to authenticated;

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  uid text not null,
  email text,
  full_name text,
  church_id text,
  request_reason text,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'cancelled')),
  retention_policy text not null default
    'Profile PII is anonymized immediately. Ministry, finance, care, attendance, safety, and audit records are retained or anonymized according to Grace Connect policy and legal obligations.',
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by text,
  notes text
);

create unique index if not exists account_deletion_requests_open_idx
  on public.account_deletion_requests (user_id)
  where status in ('pending', 'processing');

alter table public.account_deletion_requests enable row level security;

drop policy if exists "Users view own deletion requests"
  on public.account_deletion_requests;
create policy "Users view own deletion requests"
  on public.account_deletion_requests
  for select
  to authenticated
  using (user_id = auth.uid());

create or replace function public.request_account_deletion(
  request_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_uuid uuid := auth.uid();
  actor_uid text := auth.uid()::text;
  profile public.users;
  existing_request_id uuid;
  new_request_id uuid;
begin
  if actor_uuid is null then
    raise exception 'Not authenticated';
  end if;

  select *
    into profile
    from public.users
    where uid = actor_uid
       or id = actor_uuid
    limit 1;

  select id
    into existing_request_id
    from public.account_deletion_requests
    where user_id = actor_uuid
      and status in ('pending', 'processing')
    order by requested_at desc
    limit 1;

  if existing_request_id is null then
    insert into public.account_deletion_requests (
      user_id,
      uid,
      email,
      full_name,
      church_id,
      request_reason
    )
    values (
      actor_uuid,
      actor_uid,
      profile.email,
      profile."fullName",
      profile."placeId",
      nullif(trim(coalesce(request_reason, '')), '')
    )
    returning id into new_request_id;
  else
    new_request_id := existing_request_id;
  end if;

  update public.users
    set email = 'deleted+' || replace(actor_uid, '-', '') || '@graceconnect.local',
        "fullName" = 'Deleted Member',
        phone = '',
        "photoUrl" = '',
        bio = '',
        "allowMessages" = false,
        "isProfilePrivate" = true,
        "showContactInfo" = false,
        "contactInfoVisibility" = 'private',
        "showFamilyTree" = false,
        "showFamilyRelationshipTypes" = false,
        "allowFamilyLinkRequests" = false,
        "familyTreeVisibility" = 'private',
        "accountState" = 'deletion_requested'
    where uid = actor_uid
       or id = actor_uuid;

  update public.direct_conversations
    set hidden_for = array(
      select distinct value
      from unnest(coalesce(hidden_for, '{}'::text[]) || actor_uid) as value
    )
    where actor_uid = any(member_ids);

  return new_request_id;
end;
$$;

grant execute on function public.request_account_deletion(text)
  to authenticated;
