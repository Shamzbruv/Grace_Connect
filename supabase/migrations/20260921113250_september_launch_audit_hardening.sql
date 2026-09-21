-- Forward fixes for the September 20 launch changes. No production data purge.
-- A defaulted overload makes older PostgREST calls ambiguous. The new signature
-- handles the same named arguments, so retain just that implementation.
drop function public.update_church_profile(text,text,text,text,text,text,integer,text,text,text,text);
create or replace function public.update_church_profile(
  p_church_id text, p_name text, p_address text, p_denomination text,
  p_timezone text, p_about text default null, p_founded_year integer default null,
  p_contact_email text default null, p_contact_phone text default null,
  p_website_url text default null, p_service_times_note text default null,
  p_logo_url text default null, p_managing_pastor_name text default null,
  p_managing_pastor_title text default null, p_managing_pastor_since date default null
) returns jsonb language plpgsql security definer set search_path = 'public'
as $function$
declare
  actor_id uuid := auth.uid();
  target_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
  updated record;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;
  if target_church_id is null then
    target_church_id := public.get_church_id();
  end if;
  if target_church_id is null or not public.can_manage_church_members(target_church_id) then
    raise exception 'Only a pastor or church admin can update this church profile.';
  end if;

  update public.churches
  set name = nullif(trim(coalesce(p_name, name)), ''),
      display_name = nullif(trim(coalesce(p_name, display_name, name)), ''),
      address = nullif(trim(coalesce(p_address, address)), ''),
      denomination = nullif(trim(coalesce(p_denomination, denomination)), ''),
      timezone = coalesce(nullif(trim(p_timezone), ''), timezone, 'UTC'),
      about = nullif(trim(coalesce(p_about, '')), ''),
      founded_year = case
        when p_founded_year is not null
          and p_founded_year between 1500 and extract(year from now())::integer
        then p_founded_year else null end,
      contact_email = nullif(trim(coalesce(p_contact_email, '')), ''),
      contact_phone = nullif(trim(coalesce(p_contact_phone, '')), ''),
      website_url = nullif(trim(coalesce(p_website_url, '')), ''),
      service_times_note = nullif(trim(coalesce(p_service_times_note, '')), ''),
      -- A logo upload and a text edit are separate actions, so a profile
      -- save that carries no logo must not erase the existing one.
      logo_url = coalesce(nullif(trim(coalesce(p_logo_url, '')), ''), logo_url),
      managing_pastor_name = nullif(trim(coalesce(p_managing_pastor_name, managing_pastor_name, '')), ''),
      managing_pastor_title = nullif(trim(coalesce(p_managing_pastor_title, managing_pastor_title, '')), ''),
      managing_pastor_since = coalesce(p_managing_pastor_since, managing_pastor_since),
      profile_updated_at = now(),
      updated_at = now()
  where id::text = target_church_id or "placeId"::text = target_church_id
  returning * into updated;

  if updated.id is null then
    raise exception 'Church not found.';
  end if;
  return to_jsonb(updated);
end;
$function$;

revoke all on function public.update_church_profile(text,text,text,text,text,text,integer,text,text,text,text,text,text,text,date) from public,anon;
grant execute on function public.update_church_profile(text,text,text,text,text,text,integer,text,text,text,text,text,text,text,date) to authenticated;

-- Validate on timezone changes, not on every attendance lookup.
create or replace function private.validate_church_timezone()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.timezone is distinct from old.timezone and new.timezone is not null
     and not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise exception 'Choose a valid IANA timezone, such as America/Jamaica or Europe/London.' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function private.validate_church_timezone() from public,anon,authenticated;
create trigger validate_church_timezone_before_update
before update of timezone on public.churches for each row
execute function private.validate_church_timezone();

-- Logo permissions use the same membership/alias check as profile editing.
drop policy "Church leaders manage their church media" on storage.objects;
create policy "Church leaders manage their church media" on storage.objects
for insert to authenticated with check (bucket_id='church_media'
  and public.can_manage_church_members((storage.foldername(name))[1]));
drop policy "Church leaders replace their church media" on storage.objects;
create policy "Church leaders replace their church media" on storage.objects
for update to authenticated
using (bucket_id='church_media' and public.can_manage_church_members((storage.foldername(name))[1]))
with check (bucket_id='church_media' and public.can_manage_church_members((storage.foldername(name))[1]));
drop policy "Church leaders remove their church media" on storage.objects;
create policy "Church leaders remove their church media" on storage.objects
for delete to authenticated using (bucket_id='church_media'
  and public.can_manage_church_members((storage.foldername(name))[1]));

grant select on public.quote_backgrounds to anon,authenticated;
grant insert,update,delete on public.quote_backgrounds to authenticated;
-- Private social profiles still participate without exposing their identity.
create or replace function private.ranking_identity_visible(p_user text,p_scope text)
returns boolean language sql stable set search_path='' as $$
  select p_user=auth.uid()::text or p_scope='church' or not exists(
    select 1 from public.social_profiles p where p.user_id=p_user and p.visibility='private'
  );
$$;
revoke all on function private.ranking_identity_visible(text,text) from public,anon,authenticated;
create or replace function public.list_bible_streak_ranking(
  p_scope text default 'church',
  result_limit integer default 25
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  scope text := lower(coalesce(nullif(trim(p_scope), ''), 'church'));
  church text;
  capped integer := greatest(1, least(coalesce(result_limit, 25), 100));
  cutoff date;
  entries jsonb;
  viewer jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if scope not in ('church','global') then
    raise exception 'Unknown ranking scope.' using errcode = '22023';
  end if;
  church := public.grace_connect_leaderboard_church_id();
  if scope = 'church' and coalesce(trim(church), '') = '' then
    return jsonb_build_object('scope', scope, 'entries', '[]'::jsonb, 'viewer', null);
  end if;

  -- Match the calendar used by record_my_bible_reading and the local retry
  -- ledger. Switching the ranking clock alone expires valid streaks early.
  cutoff := (now() at time zone 'America/Jamaica')::date - 1;

  with ranked as (
    select
      bs.user_id::text as user_id,
      -- The viewer always sees their own full name so they can find
      -- themselves, even on a global board.
      case
        when scope = 'global' and bs.user_id <> actor
          then private.display_first_name(bs.user_name)
        else bs.user_name
      end as user_name,
      bs.photo_url,
      bs.streak_count,
      bs.last_read_date,
      coalesce(bs.last_read_date >= cutoff, false) as is_current,
      rank() over (
        order by
          coalesce(bs.last_read_date >= cutoff, false) desc,
          bs.streak_count desc,
          bs.last_read_date desc,
          bs.updated_at desc
      ) as position
    from public.bible_streaks bs
    where bs.streak_count > 0
      and not exists(select 1 from public.user_blocks b where
        (b.blocker_id=actor::text and b.blocked_user_id=bs.user_id::text) or
        (b.blocked_user_id=actor::text and b.blocker_id=bs.user_id::text))
      and (scope = 'global' or bs.church_id = church)
  ), page as (
    select * from ranked order by position, user_id limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position,
        'user_id', case when private.ranking_identity_visible(p.user_id,scope) then p.user_id end,
        'user_name', case when private.ranking_identity_visible(p.user_id,scope) then p.user_name else 'Private member' end,
        'photo_url', case when private.ranking_identity_visible(p.user_id,scope) then p.photo_url end, 'streak_count', p.streak_count,
        'last_read_date', p.last_read_date, 'is_current', p.is_current,
        'is_viewer', p.user_id = actor::text
      ) order by p.position, p.user_id) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'streak_count', r.streak_count, 'is_current', r.is_current,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'entries', entries, 'viewer', viewer);
end;
$$;
revoke all on function public.list_bible_streak_ranking(text, integer) from public, anon;
grant execute on function public.list_bible_streak_ranking(text, integer) to authenticated;

create or replace function public.list_quiz_ranking(
  p_scope text default 'church',
  p_quiz_month text default null,
  result_limit integer default 25
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  scope text := lower(coalesce(nullif(trim(p_scope), ''), 'church'));
  church text;
  capped integer := greatest(1, least(coalesce(result_limit, 25), 100));
  month_start date;
  calendar_zone text;
  month_end timestamptz;
  entries jsonb;
  viewer jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if scope not in ('church','global') then
    raise exception 'Unknown ranking scope.' using errcode = '22023';
  end if;
  church := public.grace_connect_leaderboard_church_id();
  calendar_zone := case when scope='global' then 'UTC' else 'America/Jamaica' end;
  if nullif(btrim(p_quiz_month),'') is not null and
     p_quiz_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])(-01)?$' then
    raise exception 'Use a valid YYYY-MM month.' using errcode='22023';
  end if;
  month_start := case when nullif(btrim(p_quiz_month),'') is null
    then date_trunc('month',now() at time zone calendar_zone)::date
    else (left(p_quiz_month,7)||'-01')::date end;
  month_end := (month_start + interval '1 month') at time zone calendar_zone;
  if scope = 'church' and coalesce(trim(church), '') = '' then
    return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
      'entries', '[]'::jsonb, 'viewer', null);
  end if;

  with scored as (
    select
      a.member_id,
      sum(coalesce(a.total_score, 0))::integer as total_score,
      sum(coalesce(a.correct_answers, 0))::integer as correct_answers,
      count(*) filter (where coalesce(a.total_score, 0) = 100)::integer
        as perfect_quizzes,
      count(*)::integer as quizzes_completed,
      sum(coalesce(a.total_response_time_ms, 0))::bigint as response_ms
    from public.quiz_attempts a
    where a.status = 'completed'
      and not exists(select 1 from public.user_blocks b where
        (b.blocker_id=actor::text and b.blocked_user_id=a.member_id::text) or
        (b.blocked_user_id=actor::text and b.blocker_id=a.member_id::text))
      and a.completed_at >= (month_start::timestamp at time zone calendar_zone)
      and a.completed_at < month_end
      and (scope = 'global' or coalesce(a.church_id_at_attempt, a.church_id) = church)
    group by a.member_id
  ), named as (
    select
      s.*,
      -- Matched on both keys: this table stores the auth id in `id` for some
      -- rows and as text in `uid` for others, and joining on one alone left
      -- half the board showing the 'Member' placeholder.
      (
        select coalesce(nullif(btrim(u."displayName"), ''),
                        nullif(btrim(u."fullName"), ''))
        from public.users u
        where u.uid = s.member_id::text or u.id = s.member_id
        limit 1
      ) as full_name,
      (
        select u."photoUrl"
        from public.users u
        where u.uid = s.member_id::text or u.id = s.member_id
        limit 1
      ) as photo_url
    from scored s
  ), ranked as (
    select
      n.member_id::text as user_id,
      case
        when scope = 'global' and n.member_id <> actor
          then private.display_first_name(n.full_name)
        else coalesce(n.full_name, 'Member')
      end as user_name,
      n.photo_url,
      n.total_score, n.correct_answers, n.perfect_quizzes, n.quizzes_completed,
      rank() over (
        order by n.total_score desc, n.perfect_quizzes desc, n.correct_answers desc, n.response_ms asc
      ) as position
    from named n
  ), page as (
    select * from ranked order by position, user_id limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position,
        'user_id', case when private.ranking_identity_visible(p.user_id,scope) then p.user_id end,
        'user_name', case when private.ranking_identity_visible(p.user_id,scope) then p.user_name else 'Private member' end,
        'photo_url', case when private.ranking_identity_visible(p.user_id,scope) then p.photo_url end, 'total_score', p.total_score,
        'correct_answers', p.correct_answers,
        'perfect_quizzes', p.perfect_quizzes,
        'quizzes_completed', p.quizzes_completed,
        'is_viewer', p.user_id = actor::text
      ) order by p.position, p.user_id) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'total_score', r.total_score,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
    'entries', entries, 'viewer', viewer, 'calendar_zone', calendar_zone,
    'next_month_at', month_end);
end;
$$;
revoke all on function public.list_quiz_ranking(text, text, integer) from public, anon;
grant execute on function public.list_quiz_ranking(text, text, integer) to authenticated;

-- Authorize private live discovery from the signed-in viewer, never a caller-supplied church.
create or replace function public.list_visible_live_churches(
  viewer_church_id text default null,
  result_limit integer default 30
)
returns setof public.churches
language sql
stable
security definer
set search_path = public
as $$
  with viewer as (
    -- Keep the legacy argument for client compatibility; it cannot grant access.
    select nullif(public.viewer_effective_church_id(), '') as church_id
  )
  select c.*
  from public.churches c
  cross join viewer v
  where coalesce(c."isLive", false)
    and nullif(trim(coalesce(c."liveStreamUrl", '')), '') is not null
    and coalesce(c.church_status, 'approved') = 'approved'
    and coalesce(c.public_visibility, true)
    and (
      coalesce(c.live_is_public, false)
      or (v.church_id is not null and (c.id = v.church_id or c."placeId" = v.church_id))
    )
  order by
    case
      when v.church_id is not null and (c.id = v.church_id or c."placeId" = v.church_id)
        then 0
      else 1
    end,
    c.name asc
  limit greatest(1, least(coalesce(result_limit, 30), 100));
$$;

revoke all on function public.list_visible_live_churches(text, integer) from public, anon;
grant execute on function public.list_visible_live_churches(text, integer) to authenticated;
