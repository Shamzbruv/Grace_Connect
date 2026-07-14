alter table public.grace_room_messages
  add column if not exists expires_at timestamptz;

update public.grace_room_messages
set expires_at = created_at + interval '24 hours'
where expires_at is null;

alter table public.grace_room_messages
  alter column expires_at set default (now() + interval '24 hours'),
  alter column expires_at set not null;

create index if not exists grace_room_messages_expires_idx
  on public.grace_room_messages (expires_at);

create index if not exists grace_room_messages_room_active_idx
  on public.grace_room_messages (room_id, created_at)
  where moderation_status = 'visible';

create or replace function public.set_grace_room_message_expiry()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.created_at is null then
    new.created_at := now();
  end if;

  if new.expires_at is null then
    new.expires_at := new.created_at + interval '24 hours';
  end if;

  return new;
end;
$$;

drop trigger if exists set_grace_room_message_expiry
  on public.grace_room_messages;

create trigger set_grace_room_message_expiry
before insert on public.grace_room_messages
for each row
execute function public.set_grace_room_message_expiry();

create or replace function public.delete_expired_grace_room_messages()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer := 0;
begin
  delete from public.grace_room_messages
  where coalesce(expires_at, created_at + interval '24 hours') <= now();

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

grant execute on function public.delete_expired_grace_room_messages()
  to authenticated;

drop policy if exists "Participants read room messages"
  on public.grace_room_messages;

create policy "Participants read room messages"
  on public.grace_room_messages for select to authenticated
  using (
    moderation_status = 'visible'
    and coalesce(expires_at, created_at + interval '24 hours') > now()
    and exists (
      select 1 from public.grace_room_participants p
      where p.room_id = grace_room_messages.room_id
        and p.user_id = auth.uid()::text
    )
  );

drop policy if exists "Participants send room messages"
  on public.grace_room_messages;

create policy "Participants send room messages"
  on public.grace_room_messages for insert to authenticated
  with check (
    author_id = auth.uid()::text
    and expires_at <= now() + interval '24 hours 5 minutes'
    and exists (
      select 1 from public.grace_room_participants p
      where p.room_id = grace_room_messages.room_id
        and p.user_id = auth.uid()::text
    )
  );

do $$
begin
  begin
    execute 'create extension if not exists pg_cron with schema extensions';
  exception
    when others then
      raise notice 'pg_cron is not available in this database: %', sqlerrm;
  end;

  if exists (select 1 from pg_namespace where nspname = 'cron') then
    begin
      execute
        'select cron.unschedule(''delete-expired-grace-room-messages'')';
    exception
      when others then
        null;
    end;

    begin
      execute
        'select cron.schedule(
          ''delete-expired-grace-room-messages'',
          ''*/15 * * * *'',
          ''select public.delete_expired_grace_room_messages();''
        )';
    exception
      when others then
        raise notice 'Could not schedule Grace Room cleanup: %', sqlerrm;
    end;
  end if;
end;
$$;
