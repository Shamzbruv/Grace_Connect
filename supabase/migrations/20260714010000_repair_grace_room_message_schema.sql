create extension if not exists pgcrypto;

create table if not exists public.grace_rooms (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'Grace Room',
  topic text not null default '',
  description text not null default '',
  created_by text not null default 'platform',
  status text not null default 'open',
  participant_count integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.grace_rooms
  add column if not exists subtitle text not null default '',
  add column if not exists purpose text not null default '',
  add column if not exists scripture_refs text[] not null default '{}'::text[],
  add column if not exists safety_note text not null default '',
  add column if not exists moderation_note text not null default '',
  add column if not exists restrictions text not null default '',
  add column if not exists icon_key text not null default 'forum',
  add column if not exists accent_hex text not null default '#7DB9F1',
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_platform_room boolean not null default false;

create table if not exists public.grace_room_participants (
  room_id uuid not null references public.grace_rooms(id) on delete cascade,
  user_id text not null,
  anonymous_name text not null,
  joined_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.grace_room_participants
  add column if not exists anonymous_name text not null default 'Anonymous',
  add column if not exists joined_at timestamptz not null default now(),
  add column if not exists last_seen_at timestamptz not null default now();

create table if not exists public.grace_room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.grace_rooms(id) on delete cascade,
  author_id text not null,
  anonymous_name text not null,
  body text not null,
  moderation_status text not null default 'visible',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

alter table public.grace_room_messages
  add column if not exists author_id text not null default '',
  add column if not exists anonymous_name text not null default 'Anonymous',
  add column if not exists body text not null default '',
  add column if not exists moderation_status text not null default 'visible',
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists expires_at timestamptz;

update public.grace_room_messages
set expires_at = coalesce(expires_at, created_at + interval '24 hours');

alter table public.grace_room_messages
  alter column expires_at set default (now() + interval '24 hours'),
  alter column expires_at set not null;

create index if not exists grace_room_messages_room_created_idx
  on public.grace_room_messages (room_id, created_at);

create index if not exists grace_room_messages_expires_idx
  on public.grace_room_messages (expires_at);

create index if not exists grace_room_messages_room_active_idx
  on public.grace_room_messages (room_id, created_at)
  where moderation_status = 'visible';

insert into public.grace_rooms (
  id, title, topic, description, subtitle, purpose, scripture_refs,
  safety_note, moderation_note, restrictions, icon_key, accent_hex,
  sort_order, is_platform_room, created_by, status, participant_count, metadata
)
values
  ('10000000-0000-0000-0000-000000000001', 'The Heavy Heart', 'Emotional support', 'For days when your heart feels heavy and words are hard.', 'A gentle space for sadness, pressure, and quiet overwhelm.', 'Sadness, depression, emotional weight, discouragement', array['Psalm 34:18','Psalm 42:11','Matthew 11:28-30','Isaiah 41:10','Romans 8:38-39','Psalm 40:1-3']::text[], 'If someone expresses self-harm or danger, guide them to emergency help and alert moderators.', '', '', 'heart', '#78C6A3', 1, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000002', 'Peace in the Storm', 'Anxiety and fear', 'For prayerful steadiness when life feels loud.', 'A calm room for anxiety, worry, panic, and restless thoughts.', 'Anxiety, fear, panic, worry, overthinking', array['Philippians 4:6-7','1 Peter 5:7','John 14:27','Isaiah 26:3','Psalm 56:3-4','Psalm 94:19']::text[], '', '', '', 'peace', '#7DB9F1', 2, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000003', 'Grief and Goodbye', 'Loss and comfort', 'For people walking through goodbye and grief.', 'A tender place for loss, mourning, and remembrance.', 'Bereavement, grief, death, separation, major loss', array['Psalm 147:3','Matthew 5:4','John 11:35','Revelation 21:4','Psalm 30:5','2 Corinthians 1:3-4']::text[], '', '', '', 'leaf', '#9BC3B9', 3, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000004', 'Not Alone', 'Loneliness', 'For anyone who needs to be reminded they are seen.', 'A welcoming room for isolation, rejection, and loneliness.', 'Loneliness, isolation, rejection, lack of belonging', array['Hebrews 13:5','Psalm 27:10','Ecclesiastes 4:9-10','Isaiah 43:2','Matthew 28:20','Psalm 68:6']::text[], '', '', '', 'people', '#F4B860', 4, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000005', 'Faith Under Pressure', 'Doubt and endurance', 'For honest wrestling without shame.', 'A grounded room for questions, doubt, and spiritual fatigue.', 'Doubt, spiritual fatigue, unanswered prayer, weak faith', array['Mark 9:24','Psalm 13:1-6','Isaiah 42:3','James 1:5','Hebrews 11:1','Psalm 73:26']::text[], '', 'Allow honest questions while keeping the room respectful and Christ-centered.', '', 'flame', '#B8A4FF', 5, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000006', 'Wounded by Church', 'Healing and safety', 'For healing conversations without public accusations.', 'A careful room for church hurt, betrayal, and rebuilding trust.', 'Church hurt, leadership wounds, spiritual abuse recovery', array['Ezekiel 34:11-16','Psalm 55:12-14','Psalm 55:22','Matthew 11:28-30','Colossians 3:12-14','Romans 12:18']::text[], '', '', 'Do not name churches, pastors, or individuals. Report abuse or criminal concerns privately.', 'shield', '#E7A6B8', 6, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000007', 'Marriage and Relationships', 'Relationships', 'For relationship burdens that need wisdom and prayer.', 'A supportive room for love, conflict, patience, and repair.', 'Marriage, dating, friendship conflict, reconciliation', array['1 Corinthians 13:4-7','Colossians 3:12-14','Proverbs 15:1','Ephesians 4:2-3','James 1:19-20','Ecclesiastes 4:9-10']::text[], 'If abuse or immediate danger is disclosed, direct the person to emergency and professional help.', '', '', 'rings', '#F29E7D', 7, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000008', 'Family Matters', 'Home and family', 'For people praying over family relationships.', 'A warm room for parenting, family tension, and home life.', 'Parenting, family conflict, home pressure, generational wounds', array['Ephesians 4:2-3','Colossians 3:13','Psalm 133:1','Joshua 24:15','Proverbs 22:6','Ephesians 6:1-4']::text[], '', '', '', 'home', '#8DD7CF', 8, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000009', 'Freedom Journey', 'Habits and recovery', 'For taking the next faithful step toward freedom.', 'A steady room for temptation, habits, and recovery steps.', 'Addiction recovery, temptation, unwanted patterns, accountability', array['1 Corinthians 10:13','Galatians 5:1','James 4:7','Romans 6:14','Psalm 40:1-3','John 8:36']::text[], '', '', 'No medical diagnosis, medication advice, or substance sourcing. Encourage professional support where needed.', 'path', '#8FB8ED', 9, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb),
  ('10000000-0000-0000-0000-000000000010', 'Grace After Failure', 'Restoration', 'For people who need mercy to feel possible again.', 'A hopeful room for repentance, shame, and starting again.', 'Shame, guilt, repentance, rebuilding after mistakes', array['Romans 8:1','1 John 1:9','Psalm 51:10-12','Micah 7:8','Lamentations 3:22-23','Isaiah 1:18']::text[], '', '', '', 'sunrise', '#F6C85F', 10, true, 'platform', 'open', 0, '{"platform_defined": true}'::jsonb)
on conflict (id) do update
set title = excluded.title,
    topic = excluded.topic,
    description = excluded.description,
    subtitle = excluded.subtitle,
    purpose = excluded.purpose,
    scripture_refs = excluded.scripture_refs,
    safety_note = excluded.safety_note,
    moderation_note = excluded.moderation_note,
    restrictions = excluded.restrictions,
    icon_key = excluded.icon_key,
    accent_hex = excluded.accent_hex,
    sort_order = excluded.sort_order,
    is_platform_room = true,
    created_by = 'platform',
    status = 'open',
    metadata = excluded.metadata,
    updated_at = now();

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

create or replace function public.join_grace_room(target_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id text := auth.uid()::text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.grace_rooms
    where id = target_room_id
      and is_platform_room
      and status = 'open'
  ) then
    raise exception 'Grace Room is not available';
  end if;

  insert into public.grace_room_participants (
    room_id, user_id, anonymous_name, last_seen_at
  )
  values (
    target_room_id,
    actor_id,
    'Anonymous ' || substr(replace(actor_id, '-', ''), 1, 4),
    now()
  )
  on conflict (room_id, user_id) do update
    set last_seen_at = now();

  update public.grace_rooms
  set participant_count = (
        select count(*)::integer
        from public.grace_room_participants
        where room_id = target_room_id
      ),
      updated_at = now()
  where id = target_room_id;
end;
$$;

create or replace function public.list_grace_rooms()
returns setof public.grace_rooms
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.grace_rooms
  where is_platform_room
    and status = 'open'
  order by sort_order asc, title asc;
$$;

alter table public.grace_rooms enable row level security;
alter table public.grace_room_participants enable row level security;
alter table public.grace_room_messages enable row level security;

drop policy if exists "Authenticated users read platform grace rooms"
  on public.grace_rooms;
create policy "Authenticated users read platform grace rooms"
  on public.grace_rooms for select to authenticated
  using (is_platform_room and status = 'open');

drop policy if exists "Users read own grace room participant rows"
  on public.grace_room_participants;
create policy "Users read own grace room participant rows"
  on public.grace_room_participants for select to authenticated
  using (user_id = auth.uid()::text);

drop policy if exists "Users join own grace room participant rows"
  on public.grace_room_participants;
create policy "Users join own grace room participant rows"
  on public.grace_room_participants for insert to authenticated
  with check (user_id = auth.uid()::text);

drop policy if exists "Users refresh own grace room participant rows"
  on public.grace_room_participants;
create policy "Users refresh own grace room participant rows"
  on public.grace_room_participants for update to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

drop policy if exists "Participants read room messages"
  on public.grace_room_messages;
create policy "Participants read room messages"
  on public.grace_room_messages for select to authenticated
  using (
    moderation_status = 'visible'
    and coalesce(expires_at, created_at + interval '24 hours') > now()
    and exists (
      select 1
      from public.grace_room_participants p
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
    and nullif(trim(body), '') is not null
    and expires_at <= now() + interval '24 hours 5 minutes'
    and exists (
      select 1
      from public.grace_room_participants p
      where p.room_id = grace_room_messages.room_id
        and p.user_id = auth.uid()::text
    )
  );

grant select on public.grace_rooms to authenticated;
grant select, insert, update on public.grace_room_participants to authenticated;
grant select, insert on public.grace_room_messages to authenticated;
grant execute on function public.join_grace_room(uuid) to authenticated;
grant execute on function public.list_grace_rooms() to authenticated;
grant execute on function public.delete_expired_grace_room_messages()
  to authenticated;

select pg_notify('pgrst', 'reload schema');
