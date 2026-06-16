-- Keep inbox previews correct when direct messages are deleted for everyone.

create or replace function public.refresh_direct_conversation_preview_after_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  latest_message record;
  fallback_time timestamptz;
  preview text;
begin
  select *
    into latest_message
    from public.direct_messages
    where conversation_id = old.conversation_id
      and (expires_at is null or expires_at > now())
    order by created_at desc
    limit 1;

  if latest_message.id is null then
    select created_at
      into fallback_time
      from public.direct_conversations
      where id = old.conversation_id;

    update public.direct_conversations
    set last_message = null,
        last_sender_id = null,
        last_message_at = coalesce(fallback_time, now())
    where id = old.conversation_id;

    return old;
  end if;

  preview := coalesce(
    nullif(trim(latest_message.text), ''),
    case latest_message.media_type
      when 'image' then 'Photo'
      when 'video' then 'Video'
      when 'voice' then 'Voice message'
      when 'audio' then 'Voice message'
      else 'Attachment'
    end
  );

  update public.direct_conversations
  set last_message = preview,
      last_sender_id = latest_message.sender_id,
      last_message_at = latest_message.created_at
  where id = old.conversation_id;

  return old;
end;
$$;

drop trigger if exists trg_refresh_direct_conversation_preview_after_delete
  on public.direct_messages;
create trigger trg_refresh_direct_conversation_preview_after_delete
  after delete on public.direct_messages
  for each row execute function public.refresh_direct_conversation_preview_after_delete();
