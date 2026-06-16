-- Fix direct-message access after accepted Bible Nudges and remove rejected
-- direct Storage-table deletes from cleanup triggers.

create extension if not exists pgcrypto;

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
  other_member public.users%rowtype;
  other_uid text;
  other_auth_id text;
  other_lookup_ids text[];
  conversation_key text;
  lookup_keys text[];
  existing_conversation public.direct_conversations;
  new_conversation public.direct_conversations;
  has_message_grant boolean := false;
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

  select *
    into other_member
    from public.users u
    where u.uid = clean_other_user_id
       or u.id::text = clean_other_user_id
    limit 1;

  if other_member.id is null then
    raise exception 'That member profile was not found. If this person is outside your church, send a Bible Nudge first. Once it is accepted, you can view their profile and message each other anytime';
  end if;

  other_auth_id := other_member.id::text;
  other_uid := coalesce(nullif(other_member.uid, ''), other_auth_id);

  if other_uid = actor_uid or other_auth_id = actor_uid then
    raise exception 'You cannot message yourself';
  end if;

  select array_agg(distinct value)
    into other_lookup_ids
    from unnest(array[other_uid, other_auth_id, clean_other_user_id]) as value
    where value is not null and value <> '';

  conversation_key := public.direct_message_participant_key(
    actor_uid,
    other_uid
  );

  -- Backfill the permanent message grant when either side accepted a Bible
  -- Nudge. Bible Nudge columns are uuid, so compare them as text here.
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
  select
    conversation_key,
    least(actor_uid, other_uid),
    greatest(actor_uid, other_uid),
    'bible_nudge',
    n.id,
    n.recipient_id::text,
    coalesce(n.responded_at, n.created_at, now()),
    null
  from public.bible_nudges n
  where n.status = 'accepted'
    and (
      (n.sender_id::text = actor_uid and n.recipient_id::text = any(other_lookup_ids))
      or
      (n.recipient_id::text = actor_uid and n.sender_id::text = any(other_lookup_ids))
    )
  order by n.responded_at desc nulls last, n.created_at desc
  limit 1
  on conflict (participant_key) do update
    set revoked_at = null,
        source_type = 'bible_nudge',
        source_id = coalesce(public.direct_message_grants.source_id, excluded.source_id),
        granted_by = coalesce(public.direct_message_grants.granted_by, excluded.granted_by);

  has_message_grant := public.has_direct_message_grant(actor_uid, other_uid)
    or public.has_direct_message_grant(actor_uid, other_auth_id)
    or public.has_direct_message_grant(actor_uid, clean_other_user_id);

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = actor_uid and b.blocked_user_id = any(other_lookup_ids))
       or (b.blocker_id = any(other_lookup_ids) and b.blocked_user_id = actor_uid)
  ) then
    raise exception 'Messages are not available with this member';
  end if;

  select array_agg(distinct key_value)
    into lookup_keys
    from unnest(array[
      conversation_key,
      public.direct_message_participant_key(actor_uid, other_auth_id),
      public.direct_message_participant_key(actor_uid, clean_other_user_id)
    ]) as key_value
    where key_value is not null and key_value <> '';

  select *
    into existing_conversation
    from public.direct_conversations
    where participant_key = any(lookup_keys)
    order by created_at desc
    limit 1;

  if existing_conversation.id is not null then
    update public.direct_conversations
      set hidden_for = array_remove(
        array_remove(
          array_remove(coalesce(hidden_for, '{}'::text[]), actor_uid),
          other_uid
        ),
        other_auth_id
      )
      where id = existing_conversation.id
      returning * into existing_conversation;

    return existing_conversation;
  end if;

  if coalesce(other_member."placeId", '') <> actor_church_id
      and not has_message_grant then
    raise exception 'This person is outside your church. Send a Bible Nudge first. Once both people accept, you can view their profile and message each other anytime';
  end if;

  if not coalesce(other_member."allowMessages", true)
      and not has_message_grant then
    raise exception 'This member is not accepting messages right now';
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
    array[actor_uid, other_uid],
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

-- Keep direct-message inserts aligned with the server-side conversation creator.
drop policy if exists "Members create direct conversations"
  on public.direct_conversations;
create policy "Members create direct conversations"
  on public.direct_conversations
  for insert
  to authenticated
  with check (
    created_by = auth.uid()::text
    and auth.uid()::text = any(member_ids)
    and church_id = public.get_church_id()
    and (
      select count(*)
      from public.users u
      where u.uid = any(member_ids)
        and (
          coalesce(u."allowMessages", true)
          or public.has_direct_message_grant(auth.uid()::text, u.uid)
        )
    ) = 2
    and not exists (
      select 1
      from public.user_blocks b
      where (b.blocker_id = member_ids[1] and b.blocked_user_id = member_ids[2])
         or (b.blocker_id = member_ids[2] and b.blocked_user_id = member_ids[1])
    )
  );

-- Supabase Storage objects must be deleted through the Storage API. These
-- triggers were causing cleanup RPCs to fail before the app could delete rows.
drop trigger if exists community_story_media_cleanup
  on public.community_stories;
drop trigger if exists community_post_media_cleanup
  on public.community_posts;
drop trigger if exists direct_message_media_cleanup
  on public.direct_messages;

create or replace function public.delete_community_story_media()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return old;
end;
$$;

create or replace function public.delete_community_post_media()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return old;
end;
$$;

create or replace function public.delete_direct_message_media()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  return old;
end;
$$;

create or replace function public.cleanup_expired_community_stories()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  delete from public.community_stories
    where expires_at <= now();
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.cleanup_expired_community_stories()
  to authenticated;

create or replace function public.cleanup_vanishing_content()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_messages integer := 0;
  deleted_posts integer := 0;
  deleted_stories integer := 0;
begin
  delete from public.direct_messages
    where expires_at <= now();
  get diagnostics deleted_messages = row_count;

  delete from public.community_posts
    where expires_at <= now();
  get diagnostics deleted_posts = row_count;

  deleted_stories := public.cleanup_expired_community_stories();

  return jsonb_build_object(
    'deleted_messages', deleted_messages,
    'deleted_posts', deleted_posts,
    'deleted_stories', deleted_stories
  );
end;
$$;

grant execute on function public.cleanup_vanishing_content()
  to authenticated;

notify pgrst, 'reload schema';
