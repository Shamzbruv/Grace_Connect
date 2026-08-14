-- Event reliability: idempotent server writes, canonical duplicate prevention,
-- safe event links, RSVP reminder preferences, and retryable reminder delivery.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

alter table public.events
  add column if not exists event_url text,
  add column if not exists duration_minutes integer not null default 60,
  add column if not exists creation_request_id uuid,
  add column if not exists updated_at timestamptz not null default now();

alter table public.events
  drop constraint if exists events_event_url_check,
  drop constraint if exists events_duration_minutes_check;

alter table public.events
  add constraint events_event_url_check check (
    event_url is null
    or (
      length(event_url) <= 2048
      and event_url ~* '^https://([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,63}|xn--[a-z0-9-]{2,59})(:[0-9]{1,5})?([/?#][^[:space:]]*)?$'
    )
  ),
  add constraint events_duration_minutes_check check (
    duration_minutes between 15 and 1440
  );

create or replace function public.normalize_event_title(value text)
returns text
language sql
immutable
strict
as $$
  select lower(trim(regexp_replace(value, '[[:space:]]+', ' ', 'g')));
$$;

-- Consolidate exact legacy duplicates before adding the canonical guard. The
-- oldest row remains authoritative and inherits every attendee.
drop table if exists _event_duplicate_map;
create temporary table _event_duplicate_map as
select ranked.keep_id, ranked.id as duplicate_id
from (
  select
    e.id,
    first_value(e.id) over duplicate_window as keep_id,
    row_number() over duplicate_window as duplicate_rank
  from public.events e
  window duplicate_window as (
    partition by
      e."churchId",
      coalesce(e.ministry_id, '00000000-0000-0000-0000-000000000000'::uuid),
      public.normalize_event_title(e.title),
      e.date
    order by coalesce(e."createdAt", e.date), e.id
  )
) ranked
where ranked.duplicate_rank > 1;

update public.events kept
set attendees = coalesce(
  (
    select array_agg(distinct attendee_id)
    from public.events candidate
    cross join lateral unnest(coalesce(candidate.attendees, '{}'::text[])) attendee_id
    where candidate.id = kept.id
       or candidate.id in (
         select duplicate_id
         from _event_duplicate_map
         where keep_id = kept.id
       )
  ),
  '{}'::text[]
)
where exists (
  select 1 from _event_duplicate_map where keep_id = kept.id
);

delete from public.notifications duplicate_notification
using _event_duplicate_map mapping
where duplicate_notification.entity_table = 'events'
  and duplicate_notification.entity_id = mapping.duplicate_id
  and exists (
    select 1
    from public.notifications kept_notification
    where kept_notification.user_id = duplicate_notification.user_id
      and kept_notification.type = duplicate_notification.type
      and kept_notification.entity_table = 'events'
      and kept_notification.entity_id = mapping.keep_id
  );

update public.notifications notification
set entity_id = mapping.keep_id
from _event_duplicate_map mapping
where notification.entity_table = 'events'
  and notification.entity_id = mapping.duplicate_id;

delete from public.events duplicate_event
using _event_duplicate_map mapping
where duplicate_event.id = mapping.duplicate_id;

drop table _event_duplicate_map;

create unique index if not exists events_creation_request_unique_idx
  on public.events (creation_request_id)
  where creation_request_id is not null;

-- Replace an earlier development definition if this migration is rehearsed
-- against a database where the index name already exists. The canonical
-- occurrence intentionally does not include organizer identity.
drop index if exists public.events_canonical_occurrence_unique_idx;
create unique index if not exists events_canonical_occurrence_unique_idx
  on public.events (
    "churchId",
    coalesce(ministry_id, '00000000-0000-0000-0000-000000000000'::uuid),
    public.normalize_event_title(title),
    date
  );

create or replace function public.set_event_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_event_updated_at_trigger on public.events;
create trigger set_event_updated_at_trigger
  before update of
    title, description, date, time, location, "sourceLabel",
    ministry_id, ministry_name, visible_to_all_churches,
    event_url, duration_minutes
  on public.events
  for each row execute function public.set_event_updated_at();

create or replace function public.save_event_idempotent(
  p_request_id uuid default null,
  p_event_id text default null,
  p_church_id text default null,
  p_title text default null,
  p_description text default null,
  p_start_at timestamptz default null,
  p_time_label text default null,
  p_location text default null,
  p_event_url text default null,
  p_duration_minutes integer default 60,
  p_source_label text default 'Church Event',
  p_ministry_id uuid default null,
  p_ministry_name text default '',
  p_visible_to_all_churches boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  actor_church_id text := public.get_church_id();
  normalized_title text := public.normalize_event_title(coalesce(p_title, ''));
  normalized_url text := nullif(trim(coalesce(p_event_url, '')), '');
  target_event public.events;
  existing_event public.events;
  broad_access boolean;
  is_create boolean := nullif(trim(coalesce(p_event_id, '')), '') is null;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if nullif(trim(coalesce(p_church_id, '')), '') is null
     or p_church_id <> actor_church_id then
    raise exception 'Events can only be saved for your church';
  end if;
  if normalized_title = '' or length(normalized_title) > 160 then
    raise exception 'Event title must be between 1 and 160 characters';
  end if;
  if nullif(trim(coalesce(p_description, '')), '') is null
     or length(p_description) > 5000 then
    raise exception 'Event details must be between 1 and 5000 characters';
  end if;
  if p_start_at is null then
    raise exception 'Event start time is required';
  end if;
  if p_duration_minutes is null or p_duration_minutes not between 15 and 1440 then
    raise exception 'Event duration must be between 15 and 1440 minutes';
  end if;
  if length(coalesce(p_location, '')) > 500
     or length(coalesce(p_time_label, '')) > 80
     or length(coalesce(p_source_label, '')) > 160
     or length(coalesce(p_ministry_name, '')) > 160 then
    raise exception 'One or more event fields are too long';
  end if;
  if normalized_url is not null and not (
    length(normalized_url) <= 2048
    and normalized_url ~* '^https://([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,63}|xn--[a-z0-9-]{2,59})(:[0-9]{1,5})?([/?#][^[:space:]]*)?$'
  ) then
    raise exception 'Event links must be public HTTPS links';
  end if;

  broad_access := public.has_any_role(array[
    'Pastor', 'Senior Pastor', 'Assistant Pastor', 'Acting Pastor',
    'Church Admin', 'Admin', 'Administrator', 'Secretary',
    'Church Secretary', 'Event Coordinator'
  ]) or public.has_app_privilege('createEvents');

  if not broad_access and not (
    p_ministry_id is not null
    and public.is_ministry_manager(p_church_id, p_ministry_id, 'events')
  ) then
    raise exception 'You do not have permission to save this event';
  end if;

  if p_ministry_id is not null and not exists (
    select 1 from public.ministries ministry
    where ministry.id = p_ministry_id
      and ministry.church_id = p_church_id
      and ministry.status = 'active'
  ) then
    raise exception 'The selected ministry is not available';
  end if;

  if is_create then
    if p_request_id is null then
      raise exception 'A creation request id is required';
    end if;

    perform pg_advisory_xact_lock(
      hashtextextended('event-request:' || p_request_id::text, 0)
    );
    select event.* into existing_event
    from public.events event
    where event.creation_request_id = p_request_id
    limit 1;
    if found then
      return jsonb_build_object(
        'event', to_jsonb(existing_event),
        'created', false,
        'reused_existing', true
      );
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      concat_ws('|', p_church_id, coalesce(p_ministry_id::text, ''),
        normalized_title, p_start_at::text),
      0
    ));
    select event.* into existing_event
    from public.events event
    where event."churchId" = p_church_id
      and coalesce(event.ministry_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(p_ministry_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and public.normalize_event_title(event.title) = normalized_title
      and event.date = p_start_at
    order by event."createdAt", event.id
    limit 1;
    if found then
      return jsonb_build_object(
        'event', to_jsonb(existing_event),
        'created', false,
        'reused_existing', true
      );
    end if;

    begin
      insert into public.events (
        id, title, description, date, time, location,
        "churchId", "organizerId", "sourceLabel", "createdAt", attendees,
        ministry_id, ministry_name, visible_to_all_churches,
        event_url, duration_minutes, creation_request_id, updated_at
      ) values (
        p_request_id::text,
        trim(p_title), trim(p_description), p_start_at,
        trim(coalesce(p_time_label, '')), trim(coalesce(p_location, '')),
        p_church_id, actor_id::text,
        coalesce(nullif(trim(coalesce(p_source_label, '')), ''), 'Church Event'),
        now(), '{}'::text[], p_ministry_id, trim(coalesce(p_ministry_name, '')),
        coalesce(p_visible_to_all_churches, false), normalized_url,
        p_duration_minutes, p_request_id, now()
      ) returning * into target_event;
    exception when unique_violation then
      -- A legacy client can race without taking our advisory lock. Convert the
      -- database uniqueness conflict into the same successful idempotent
      -- response instead of surfacing a duplicate error to the organizer.
      select event.* into existing_event
      from public.events event
      where event.creation_request_id = p_request_id
         or (
           event."churchId" = p_church_id
           and coalesce(
             event.ministry_id,
             '00000000-0000-0000-0000-000000000000'::uuid
           ) = coalesce(
             p_ministry_id,
             '00000000-0000-0000-0000-000000000000'::uuid
           )
           and public.normalize_event_title(event.title) = normalized_title
           and event.date = p_start_at
         )
      order by
        case when event.creation_request_id = p_request_id then 0 else 1 end,
        event."createdAt",
        event.id
      limit 1;
      if not found then
        raise;
      end if;
      return jsonb_build_object(
        'event', to_jsonb(existing_event),
        'created', false,
        'reused_existing', true
      );
    end;

    return jsonb_build_object(
      'event', to_jsonb(target_event),
      'created', true,
      'reused_existing', false
    );
  end if;

  select event.* into target_event
  from public.events event
  where event.id = p_event_id
  for update;
  if not found or target_event."churchId" <> actor_church_id then
    raise exception 'Event not found';
  end if;
  if not broad_access and not (
    target_event.ministry_id is not null
    and public.is_ministry_manager(
      target_event."churchId", target_event.ministry_id, 'events'
    )
  ) then
    raise exception 'You do not have permission to update this event';
  end if;
  if not broad_access and not (
    p_ministry_id is not null
    and public.is_ministry_manager(
      target_event."churchId", p_ministry_id, 'events'
    )
  ) then
    raise exception 'You cannot move this event to an unmanaged ministry';
  end if;

  if exists (
    select 1 from public.events event
    where event.id <> target_event.id
      and event."churchId" = target_event."churchId"
      and coalesce(event.ministry_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(p_ministry_id, '00000000-0000-0000-0000-000000000000'::uuid)
      and public.normalize_event_title(event.title) = normalized_title
      and event.date = p_start_at
  ) then
    raise exception 'An identical event is already scheduled';
  end if;

  update public.events event
  set title = trim(p_title),
      description = trim(p_description),
      date = p_start_at,
      time = trim(coalesce(p_time_label, '')),
      location = trim(coalesce(p_location, '')),
      "sourceLabel" = coalesce(
        nullif(trim(coalesce(p_source_label, '')), ''), 'Church Event'
      ),
      ministry_id = p_ministry_id,
      ministry_name = trim(coalesce(p_ministry_name, '')),
      visible_to_all_churches = coalesce(p_visible_to_all_churches, false),
      event_url = normalized_url,
      duration_minutes = p_duration_minutes
  where event.id = target_event.id
  returning * into target_event;

  return jsonb_build_object(
    'event', to_jsonb(target_event),
    'created', false,
    'reused_existing', false
  );
end;
$$;

create table if not exists public.event_rsvps (
  event_id text not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_minutes integer not null default 1440
    check (reminder_minutes in (30, 120, 1440)),
  app_reminder_enabled boolean not null default true,
  reminder_version uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

insert into public.event_rsvps (event_id, user_id)
select distinct event.id, member.id
from public.events event
cross join lateral unnest(coalesce(event.attendees, '{}'::text[])) attendee_id
join public.users member
  on member.uid = attendee_id
  or member.id::text = attendee_id
on conflict (event_id, user_id) do nothing;

alter table public.event_rsvps enable row level security;
drop policy if exists "event rsvps are rpc only" on public.event_rsvps;
create policy "event rsvps are rpc only"
  on public.event_rsvps
  for all
  using (false)
  with check (false);

create table if not exists public.event_reminder_deliveries (
  event_id text not null,
  user_id uuid not null,
  reminder_minutes integer not null,
  reminder_version uuid not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer not null default 0,
  claimed_at timestamptz,
  claim_token uuid,
  sent_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id),
  foreign key (event_id, user_id)
    references public.event_rsvps(event_id, user_id) on delete cascade
);

alter table public.event_reminder_deliveries enable row level security;
drop policy if exists "event reminder deliveries are service only"
  on public.event_reminder_deliveries;
create policy "event reminder deliveries are service only"
  on public.event_reminder_deliveries
  for all
  using (false)
  with check (false);

alter table public.notifications
  add column if not exists event_reminder_version uuid;

drop index if exists public.notifications_one_event_rsvp_reminder_idx;
create unique index notifications_one_event_rsvp_reminder_idx
  on public.notifications (
    user_id, type, entity_table, entity_id, event_reminder_version
  )
  where type = 'event_rsvp_reminder'
    and entity_table = 'events'
    and event_reminder_version is not null;

create or replace function public.reset_event_reminders_after_reschedule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A new start instant is a new reminder lifecycle. Old attempts cannot
  -- complete the new delivery because every RSVP receives a fresh version and
  -- every future delivery receives a new claim token.
  delete from public.event_reminder_deliveries delivery
  where delivery.event_id = new.id;

  update public.event_rsvps rsvp
  set reminder_version = gen_random_uuid(),
      updated_at = now()
  where rsvp.event_id = new.id;

  delete from public.notifications notification
  where notification.type = 'event_rsvp_reminder'
    and notification.entity_table = 'events'
    and notification.entity_id = new.id
    and not notification.is_read;

  return new;
end;
$$;

drop trigger if exists reset_event_reminders_after_reschedule_trigger
  on public.events;
create trigger reset_event_reminders_after_reschedule_trigger
  after update of date on public.events
  for each row
  when (old.date is distinct from new.date)
  execute function public.reset_event_reminders_after_reschedule();

create or replace function public.rsvp_event_with_reminder(
  target_event_id text,
  is_joining boolean,
  reminder_minutes integer default 1440
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  actor_church_id text := public.get_church_id();
  target_event public.events;
  previous_reminder_version uuid;
  active_reminder_version uuid;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if reminder_minutes not in (30, 120, 1440) then
    raise exception 'Unsupported event reminder time';
  end if;

  select event.* into target_event
  from public.events event
  where event.id = target_event_id
  for update;
  if not found then
    raise exception 'Event not found';
  end if;
  if target_event."churchId" <> actor_church_id
     and not coalesce(target_event.visible_to_all_churches, false) then
    raise exception 'You cannot RSVP to a private event outside your church';
  end if;
  if is_joining and target_event.date <= now() then
    raise exception 'This event has already started';
  end if;

  if is_joining then
    select rsvp.reminder_version
      into previous_reminder_version
    from public.event_rsvps rsvp
    where rsvp.event_id = target_event.id
      and rsvp.user_id = actor_id;

    insert into public.event_rsvps (
      event_id, user_id, reminder_minutes, app_reminder_enabled,
      reminder_version, created_at, updated_at
    ) values (
      target_event.id, actor_id, reminder_minutes, true,
      gen_random_uuid(), now(), now()
    )
    on conflict (event_id, user_id) do update
      set reminder_minutes = excluded.reminder_minutes,
          app_reminder_enabled = true,
          reminder_version = case
            when public.event_rsvps.reminder_minutes
                   is distinct from excluded.reminder_minutes
              or not public.event_rsvps.app_reminder_enabled
            then gen_random_uuid()
            else public.event_rsvps.reminder_version
          end,
          updated_at = now()
    returning public.event_rsvps.reminder_version
      into active_reminder_version;

    if previous_reminder_version is not null
       and previous_reminder_version is distinct from active_reminder_version then
      delete from public.event_reminder_deliveries delivery
      where delivery.event_id = target_event.id
        and delivery.user_id = actor_id;
      delete from public.notifications notification
      where notification.user_id = actor_id
        and notification.type = 'event_rsvp_reminder'
        and notification.entity_table = 'events'
        and notification.entity_id = target_event.id
        and not notification.is_read;
    end if;

    update public.events event
    set attendees = case
      when actor_id::text = any(coalesce(event.attendees, '{}'::text[]))
        then coalesce(event.attendees, '{}'::text[])
      else array_append(coalesce(event.attendees, '{}'::text[]), actor_id::text)
    end
    where event.id = target_event.id;
  else
    delete from public.event_rsvps rsvp
    where rsvp.event_id = target_event.id
      and rsvp.user_id = actor_id;
    update public.events event
    set attendees = array_remove(
      coalesce(event.attendees, '{}'::text[]), actor_id::text
    )
    where event.id = target_event.id;
    delete from public.notifications notification
    where notification.user_id = actor_id
      and notification.type = 'event_rsvp_reminder'
      and notification.entity_table = 'events'
      and notification.entity_id = target_event.id
      and not notification.is_read;
  end if;

  return jsonb_build_object(
    'event_id', target_event.id,
    'joined', is_joining,
    'reminder_minutes', case when is_joining then reminder_minutes else null end,
    'reminder_version', case
      when is_joining then active_reminder_version else null
    end
  );
end;
$$;

create or replace function public.rsvp_event(
  target_event_id text,
  is_joining boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.rsvp_event_with_reminder(
    target_event_id,
    is_joining,
    1440
  );
end;
$$;

create or replace function public.claim_due_event_reminders(
  p_limit integer default 100
)
returns table (
  event_id text,
  user_id uuid,
  reminder_minutes integer,
  reminder_version uuid,
  claim_token uuid,
  event_title text,
  event_start timestamptz,
  event_location text
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  candidate record;
  claimed_id text;
  active_claim_token uuid;
begin
  for candidate in
    select
      rsvp.event_id,
      rsvp.user_id,
      rsvp.reminder_minutes,
      rsvp.reminder_version,
      event.title,
      event.date,
      event.location,
      event."churchId"
    from public.event_rsvps rsvp
    join public.events event on event.id = rsvp.event_id
    left join public.event_reminder_deliveries delivery
      on delivery.event_id = rsvp.event_id
     and delivery.user_id = rsvp.user_id
    where rsvp.app_reminder_enabled
      and event.date > now()
      and event.date - make_interval(mins => rsvp.reminder_minutes) <= now()
      and (
        delivery.event_id is null
        or delivery.reminder_version is distinct from rsvp.reminder_version
        or delivery.status in ('pending', 'failed')
        or (
          delivery.status = 'processing'
          and delivery.claimed_at < now() - interval '15 minutes'
        )
      )
      and (
        delivery.reminder_version is distinct from rsvp.reminder_version
        or coalesce(delivery.attempt_count, 0) < 12
      )
    order by event.date, rsvp.created_at
    for update of rsvp skip locked
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  loop
    claimed_id := null;
    active_claim_token := null;
    insert into public.event_reminder_deliveries (
      event_id, user_id, reminder_minutes, reminder_version,
      status, attempt_count, claimed_at, claim_token,
      error_message, created_at, updated_at
    ) values (
      candidate.event_id, candidate.user_id, candidate.reminder_minutes,
      candidate.reminder_version, 'processing', 1, now(), gen_random_uuid(),
      null, now(), now()
    )
    on conflict (event_id, user_id) do update
      set reminder_minutes = excluded.reminder_minutes,
          reminder_version = excluded.reminder_version,
          status = 'processing',
          attempt_count = case
            when public.event_reminder_deliveries.reminder_version
                   is distinct from excluded.reminder_version
              then 1
            else public.event_reminder_deliveries.attempt_count + 1
          end,
          claimed_at = now(),
          claim_token = gen_random_uuid(),
          error_message = null,
          updated_at = now()
      where public.event_reminder_deliveries.reminder_version
              is distinct from excluded.reminder_version
         or public.event_reminder_deliveries.status in ('pending', 'failed')
         or (
           public.event_reminder_deliveries.status = 'processing'
           and public.event_reminder_deliveries.claimed_at
               < now() - interval '15 minutes'
         )
    returning
      public.event_reminder_deliveries.event_id,
      public.event_reminder_deliveries.claim_token
    into claimed_id, active_claim_token;

    if claimed_id is null then
      continue;
    end if;

    insert into public.notifications (
      user_id, actor_id, actor_name, type, title, body, place_id,
      entity_table, entity_id, route, event_reminder_version
    ) values (
      candidate.user_id,
      null,
      'Grace Connect',
      'event_rsvp_reminder',
      'Your RSVP event is coming up',
      candidate.title || ' starts ' ||
        to_char(candidate.date at time zone 'America/Jamaica',
          'FMDay, FMMonth FMDD at FMHH12:MI AM') ||
        case when nullif(trim(coalesce(candidate.location, '')), '') is null
          then '' else ' · ' || trim(candidate.location) end,
      candidate."churchId",
      'events',
      candidate.event_id,
      '/events',
      candidate.reminder_version
    ) on conflict do nothing;

    event_id := candidate.event_id;
    user_id := candidate.user_id;
    reminder_minutes := candidate.reminder_minutes;
    reminder_version := candidate.reminder_version;
    claim_token := active_claim_token;
    event_title := candidate.title;
    event_start := candidate.date;
    event_location := candidate.location;
    return next;
  end loop;
end;
$$;

create or replace function public.complete_event_reminder_delivery(
  p_event_id text,
  p_user_id uuid,
  p_claim_token uuid,
  p_sent boolean,
  p_error text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_rows integer;
begin
  update public.event_reminder_deliveries
  set status = case when p_sent then 'sent' else 'failed' end,
      sent_at = case when p_sent then now() else null end,
      error_message = case
        when p_sent then null
        else left(coalesce(p_error, 'Push delivery failed'), 500)
      end,
      updated_at = now()
  where event_id = p_event_id
    and user_id = p_user_id
    and claim_token = p_claim_token
    and status = 'processing';
  get diagnostics updated_rows = row_count;
  return updated_rows = 1;
end;
$$;

revoke all on table public.event_rsvps from public, anon, authenticated;
revoke all on table public.event_reminder_deliveries
  from public, anon, authenticated;
grant all on table public.event_rsvps to service_role;
grant all on table public.event_reminder_deliveries to service_role;

-- All event creation and detail updates now pass through the guarded RPC.
-- Select/delete keep their existing RLS behavior, and RSVP mutations use the
-- dedicated security-definer function below.
revoke insert, update on table public.events from public, anon, authenticated;

revoke all on function public.normalize_event_title(text)
  from public, anon, authenticated;
revoke all on function public.set_event_updated_at()
  from public, anon, authenticated;
revoke all on function public.reset_event_reminders_after_reschedule()
  from public, anon, authenticated;
revoke all on function public.save_event_idempotent(
  uuid, text, text, text, text, timestamptz, text, text, text, integer,
  text, uuid, text, boolean
) from public, anon;
grant execute on function public.save_event_idempotent(
  uuid, text, text, text, text, timestamptz, text, text, text, integer,
  text, uuid, text, boolean
) to authenticated;
revoke all on function public.rsvp_event_with_reminder(text, boolean, integer)
  from public, anon;
grant execute on function public.rsvp_event_with_reminder(text, boolean, integer)
  to authenticated;
revoke all on function public.rsvp_event(text, boolean) from public, anon;
grant execute on function public.rsvp_event(text, boolean) to authenticated;
revoke all on function public.claim_due_event_reminders(integer)
  from public, anon, authenticated;
grant execute on function public.claim_due_event_reminders(integer)
  to service_role;
revoke all on function public.complete_event_reminder_delivery(
  text, uuid, uuid, boolean, text
) from public, anon, authenticated;
grant execute on function public.complete_event_reminder_delivery(
  text, uuid, uuid, boolean, text
) to service_role;

do $$
begin
  if exists (
    select 1 from cron.job where jobname = 'event-rsvp-reminder-delivery'
  ) then
    perform cron.unschedule('event-rsvp-reminder-delivery');
  end if;
end;
$$;

select cron.schedule(
  'event-rsvp-reminder-delivery',
  '*/10 * * * *',
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
    ) || '/functions/v1/send-event-reminders',
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
