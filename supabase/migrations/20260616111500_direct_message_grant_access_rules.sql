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
  other_member public.users%rowtype;
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

  conversation_key := public.direct_message_participant_key(
    actor_uid,
    clean_other_user_id
  );

  insert into public.direct_message_grants (
    participant_key,
    user_a,
    user_b,
    source_type,
    source_id,
    granted_by
  )
  select
    conversation_key,
    least(actor_uid, clean_other_user_id),
    greatest(actor_uid, clean_other_user_id),
    'bible_nudge',
    n.id,
    n.recipient_id
  from public.bible_nudges n
  where n.status = 'accepted'
    and (
      (n.sender_id = actor_uid and n.recipient_id = clean_other_user_id)
      or
      (n.sender_id = clean_other_user_id and n.recipient_id = actor_uid)
    )
  order by n.responded_at desc nulls last, n.created_at desc
  limit 1
  on conflict (participant_key) do update
    set source_type = excluded.source_type,
        source_id = coalesce(public.direct_message_grants.source_id, excluded.source_id),
        granted_by = coalesce(public.direct_message_grants.granted_by, excluded.granted_by);

  has_message_grant := public.has_direct_message_grant(
    actor_uid,
    clean_other_user_id
  );

  select *
    into other_member
    from public.users u
    where u.uid = clean_other_user_id
    limit 1;

  if other_member.uid is null then
    raise exception 'That member profile was not found';
  end if;

  if exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = actor_uid and b.blocked_user_id = clean_other_user_id)
       or (b.blocker_id = clean_other_user_id and b.blocked_user_id = actor_uid)
  ) then
    raise exception 'Messages are not available with this member';
  end if;

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

  if coalesce(other_member."placeId", '') <> actor_church_id
      and not has_message_grant then
    raise exception 'Send a Bible Nudge first. Once both people accept, you can view this cross-church member and message each other anytime';
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
