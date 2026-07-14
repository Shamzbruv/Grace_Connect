create extension if not exists pgcrypto;

create table if not exists public.social_follows (
  follower_id text not null,
  following_id text not null,
  status text not null default 'accepted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  check (follower_id <> following_id)
);

create table if not exists public.social_saved_items (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  entity_type text not null,
  entity_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id)
);

alter table public.social_follows enable row level security;
alter table public.social_saved_items enable row level security;

drop policy if exists "Users read own social follows" on public.social_follows;
create policy "Users read own social follows"
  on public.social_follows for select to authenticated
  using (follower_id = auth.uid()::text or following_id = auth.uid()::text);

drop policy if exists "Users manage follows they start" on public.social_follows;
create policy "Users manage follows they start"
  on public.social_follows for all to authenticated
  using (follower_id = auth.uid()::text)
  with check (follower_id = auth.uid()::text);

drop policy if exists "Users manage own saved items" on public.social_saved_items;
create policy "Users manage own saved items"
  on public.social_saved_items for all to authenticated
  using (user_id = auth.uid()::text)
  with check (user_id = auth.uid()::text);

grant select, insert, update, delete on public.social_follows to authenticated;
grant select, insert, delete on public.social_saved_items to authenticated;

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

update public.grace_rooms
set status = 'retired',
    updated_at = now()
where coalesce(is_platform_room, false) = false;

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

drop policy if exists "Users create grace rooms" on public.grace_rooms;
drop policy if exists "Authenticated users read open grace rooms" on public.grace_rooms;
create policy "Authenticated users read platform grace rooms"
  on public.grace_rooms for select to authenticated
  using (is_platform_room and status = 'open');

revoke insert, update, delete on public.grace_rooms from authenticated;
grant select on public.grace_rooms to authenticated;

drop function if exists public.create_grace_room(text, text, text);

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

  insert into public.grace_room_participants (room_id, user_id, anonymous_name, last_seen_at)
  values (target_room_id, actor_id, 'Anonymous ' || substr(replace(actor_id, '-', ''), 1, 4), now())
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

grant execute on function public.join_grace_room(uuid) to authenticated;
grant execute on function public.list_grace_rooms() to authenticated;

create or replace function public.get_community_feed(
  feed_mode text default 'discover',
  viewer_church_id text default null,
  target_circle_id text default null,
  result_limit integer default 75
)
returns setof public.community_posts
language sql
stable
security definer
set search_path = public
as $$
  select p.*
  from public.community_posts p
  where (p.expires_at is null or p.expires_at > now())
    and (
      case
        when feed_mode = 'church' then
          viewer_church_id is not null and p.place_id = viewer_church_id
        when feed_mode = 'circle' then
          target_circle_id is not null and p.circle_id::text = target_circle_id
        when feed_mode = 'following' then
          exists (
            select 1
            from public.social_follows f
            where f.follower_id = auth.uid()::text
              and f.following_id = p.author_id::text
              and f.status = 'accepted'
          )
          or exists (
            select 1
            from public.grace_circle_members m
            where m.user_id = auth.uid()::text
              and m.status = 'active'
              and p.circle_id is not null
              and m.circle_id = p.circle_id
          )
        else
          p.visible_to_all_churches or p.scope in ('global', 'discover', 'public')
      end
    )
  order by p.created_at desc
  limit greatest(1, least(coalesce(result_limit, 75), 200));
$$;

grant execute on function public.get_community_feed(text, text, text, integer)
  to authenticated;

drop policy if exists "Group admins delete study groups" on public.study_groups;
create policy "Group admins delete study groups"
  on public.study_groups for delete to authenticated
  using (
    "churchId" = public.get_church_id()
    and (
      auth.uid()::text = "leaderId"
      or auth.uid()::text = any("adminIds")
      or public.has_any_role(array['Pastor', 'Senior Pastor', 'Administrator', 'Secretary'])
    )
  );

drop policy if exists "Authors and leaders delete prayers" on public.prayer_requests;
create policy "Authors and leaders delete prayers"
  on public.prayer_requests for delete to authenticated
  using (
    "userId" = auth.uid()::text
    or (
      "churchId" = public.get_church_id()
      and public.has_any_role(array['Pastor', 'Senior Pastor', 'Prayer Warrior', 'Secretary'])
    )
  );

drop policy if exists "Authors and care leaders delete counseling" on public.counseling_requests;
create policy "Authors and care leaders delete counseling"
  on public.counseling_requests for delete to authenticated
  using (
    "userId" = auth.uid()::text
    or (
      "churchId" = public.get_church_id()
      and public.has_any_role(array['Pastor', 'Senior Pastor', 'Counselor', 'Care Counseling Coordinator', 'Secretary'])
    )
  );

grant delete on public.study_groups to authenticated;
grant delete on public.testimonies to authenticated;
grant delete on public.prayer_requests to authenticated;
grant delete on public.counseling_requests to authenticated;

create or replace function public.developer_list_reported_users()
returns table (
  reported_user_id text,
  reported_name text,
  reported_email text,
  report_count integer,
  latest_reported_at timestamptz,
  reports jsonb,
  posts jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  dev public.developer_accounts;
begin
  select *
    into dev
    from public.require_developer(array['super_developer', 'support_developer', 'security_admin', 'read_only_support']);

  return query
  with report_base as (
    select cr.*, u."fullName", u.email
    from public.content_reports cr
    left join public.users u on u.uid = cr.reported_user_id
    where nullif(trim(coalesce(cr.reported_user_id, '')), '') is not null
  ),
  grouped as (
    select
      rb.reported_user_id,
      max(rb."fullName") as reported_name,
      max(rb.email) as reported_email,
      count(*)::integer as report_count,
      max(rb.created_at) as latest_reported_at,
      jsonb_agg(
        jsonb_build_object(
          'id', rb.id,
          'church_id', rb.church_id,
          'reporter_id', rb.reporter_id,
          'content_type', rb.content_type,
          'content_id', rb.content_id,
          'reason', rb.reason,
          'description', rb.description,
          'status', rb.status,
          'created_at', rb.created_at
        )
        order by rb.created_at desc
      ) as reports
    from report_base rb
    group by rb.reported_user_id
  )
  select
    g.reported_user_id,
    coalesce(g.reported_name, '') as reported_name,
    coalesce(g.reported_email, '') as reported_email,
    g.report_count,
    g.latest_reported_at,
    g.reports,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', p.id,
            'content', p.content,
            'scope', p.scope,
            'visible_to_all_churches', p.visible_to_all_churches,
            'created_at', p.created_at
          )
          order by p.created_at desc
        )
        from (
          select *
          from public.community_posts
          where author_id::text = g.reported_user_id
          order by created_at desc
          limit 50
        ) p
      ),
      '[]'::jsonb
    ) as posts
  from grouped g
  order by g.latest_reported_at desc;
end;
$$;

create or replace function public.developer_update_content_report_status(
  p_report_id text,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  dev public.developer_accounts;
  report_uuid uuid;
  normalized_status text := lower(trim(coalesce(p_status, '')));
begin
  select *
    into dev
    from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  if normalized_status not in ('pending', 'reviewed', 'dismissed', 'action_taken') then
    raise exception 'Invalid report status';
  end if;

  report_uuid := p_report_id::uuid;

  update public.content_reports
  set status = normalized_status,
      reviewed_by = auth.uid()::text,
      reviewed_at = now()
  where id = report_uuid;

  perform public.log_developer_action(
    'content_report_status_updated',
    'content_report',
    p_report_id,
    jsonb_build_object('status', normalized_status, 'developer', dev.email)
  );
end;
$$;

grant execute on function public.developer_list_reported_users() to authenticated;
grant execute on function public.developer_update_content_report_status(text, text)
  to authenticated;

notify pgrst, 'reload schema';
