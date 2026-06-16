-- Repair stale inbox previews that existed before preview refresh triggers.

with latest_visible_message as (
  select distinct on (conversation_id)
    conversation_id,
    sender_id,
    created_at,
    coalesce(
      nullif(trim(text), ''),
      case media_type
        when 'image' then 'Photo'
        when 'video' then 'Video'
        when 'voice' then 'Voice message'
        when 'audio' then 'Voice message'
        else 'Attachment'
      end
    ) as preview
  from public.direct_messages
  where expires_at is null or expires_at > now()
  order by conversation_id, created_at desc
)
update public.direct_conversations c
set last_message = latest.preview,
    last_sender_id = latest.sender_id,
    last_message_at = latest.created_at
from latest_visible_message latest
where c.id = latest.conversation_id
  and (
    c.last_message is distinct from latest.preview
    or c.last_sender_id is distinct from latest.sender_id
    or c.last_message_at is distinct from latest.created_at
  );

update public.direct_conversations c
set last_message = null,
    last_sender_id = null,
    last_message_at = c.created_at
where not exists (
    select 1
    from public.direct_messages m
    where m.conversation_id = c.id
      and (m.expires_at is null or m.expires_at > now())
  )
  and (
    c.last_message is not null
    or c.last_sender_id is not null
    or c.last_message_at is distinct from c.created_at
  );
