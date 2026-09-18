-- Global scope for people with no church, plus church/global rankings that
-- always tell the viewer their own position even when it is off the page.

-- ---------------------------------------------------------------------------
-- Testimonies: an explicit scope. Every existing row stays church-only.
-- ---------------------------------------------------------------------------
alter table public.testimonies
  add column if not exists scope text not null default 'church';

alter table public.testimonies drop constraint if exists testimonies_scope_check;
alter table public.testimonies
  add constraint testimonies_scope_check check (scope in ('church','global'));

alter table public.testimonies alter column church_id drop not null;

-- A global testimony belongs to no church; a church testimony must name one.
-- This is what keeps historical church testimonies out of the global feed:
-- they were all written with a church_id, so they can never be scope 'global'.
alter table public.testimonies drop constraint if exists testimonies_scope_church_check;
alter table public.testimonies add constraint testimonies_scope_church_check check (
  (scope = 'church' and church_id is not null)
  or (scope = 'global' and church_id is null)
);

create index if not exists testimonies_scope_created_idx
  on public.testimonies (scope, created_at desc);

drop policy if exists "Church members view testimonies" on public.testimonies;
drop policy if exists "Church members add testimonies" on public.testimonies;
drop policy if exists "Authors and pastors delete testimonies" on public.testimonies;

create policy "View global or own church testimonies"
  on public.testimonies for select to authenticated
  using (
    scope = 'global'
    or (scope = 'church' and church_id = public.get_church_id())
  );

create policy "Post global or own church testimonies"
  on public.testimonies for insert to authenticated
  with check (
    author_id = (select auth.uid())::text
    and nullif(trim(content), '') is not null
    and (
      (scope = 'global' and church_id is null)
      or (scope = 'church' and church_id = public.get_church_id())
    )
  );

-- Pastors moderate their own church only. A global testimony is the author's.
create policy "Authors and pastors delete testimonies"
  on public.testimonies for delete to authenticated
  using (
    author_id = (select auth.uid())::text
    or (
      scope = 'church'
      and church_id = public.get_church_id()
      and public.has_any_role(array['Pastor','Senior Pastor'])
    )
  );

-- ---------------------------------------------------------------------------
-- Rankings. Both return the page plus the viewer's own rank and the total,
-- so someone in 400th place still sees where they stand.
-- ---------------------------------------------------------------------------
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

  with ranked as (
    select
      bs.user_id::text as user_id,
      bs.user_name,
      bs.photo_url,
      bs.streak_count,
      bs.last_read_date,
      rank() over (
        order by bs.streak_count desc, bs.last_read_date desc, bs.updated_at desc
      ) as position
    from public.bible_streaks bs
    where bs.streak_count > 0
      -- Recency keeps a stale streak from outranking an active one. Global
      -- uses UTC so no single region's calendar decides who is "current".
      and bs.last_read_date >= (
        case when scope = 'church'
          then (timezone(private.church_timezone(church), now()))::date
          else (now() at time zone 'UTC')::date
        end
      ) - 1
      and (scope = 'global' or bs.church_id = church)
  ), page as (
    select * from ranked order by position limit capped
  )
  -- One statement: a CTE is not visible to a second, separate query.
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position, 'user_id', p.user_id, 'user_name', p.user_name,
        'photo_url', p.photo_url, 'streak_count', p.streak_count,
        'last_read_date', p.last_read_date, 'is_viewer', p.user_id = actor::text
      ) order by p.position) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'streak_count', r.streak_count,
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
  entries jsonb;
  viewer jsonb;
begin
  if actor is null then
    raise exception 'Authentication is required.' using errcode = '42501';
  end if;
  if scope not in ('church','global') then
    raise exception 'Unknown ranking scope.' using errcode = '22023';
  end if;
  month_start := date_trunc('month',
    coalesce(to_date(nullif(trim(p_quiz_month), ''), 'YYYY-MM'), (now() at time zone 'UTC')::date)
  )::date;
  church := public.grace_connect_leaderboard_church_id();
  if scope = 'church' and coalesce(trim(church), '') = '' then
    return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
      'entries', '[]'::jsonb, 'viewer', null);
  end if;

  with scored as (
    select
      a.member_id,
      sum(coalesce(a.total_score, 0))::integer as total_score,
      sum(coalesce(a.correct_answers, 0))::integer as correct_answers,
      sum(coalesce(a.total_response_time_ms, 0))::bigint as response_ms
    from public.quiz_attempts a
    where a.status = 'completed'
      and a.completed_at >= month_start
      and a.completed_at < (month_start + interval '1 month')
      and (scope = 'global' or coalesce(a.church_id_at_attempt, a.church_id) = church)
    group by a.member_id
  ), ranked as (
    select
      s.member_id::text as user_id,
      coalesce(nullif(trim(u."displayName"), ''), nullif(trim(u."fullName"), ''), 'Member') as user_name,
      u."photoUrl" as photo_url,
      s.total_score, s.correct_answers,
      rank() over (
        order by s.total_score desc, s.correct_answers desc, s.response_ms asc
      ) as position
    from scored s
    left join public.users u on u.uid = s.member_id::text
    where s.total_score > 0
  ), page as (
    select * from ranked order by position limit capped
  )
  select
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'rank', p.position, 'user_id', p.user_id, 'user_name', p.user_name,
        'photo_url', p.photo_url, 'total_score', p.total_score,
        'correct_answers', p.correct_answers, 'is_viewer', p.user_id = actor::text
      ) order by p.position) from page p
    ), '[]'::jsonb),
    (
      select jsonb_build_object(
        'rank', r.position, 'total_score', r.total_score,
        'total', (select count(*) from ranked)
      ) from ranked r where r.user_id = actor::text
    )
  into entries, viewer;

  return jsonb_build_object('scope', scope, 'month', to_char(month_start,'YYYY-MM'),
    'entries', entries, 'viewer', viewer);
end;
$$;
revoke all on function public.list_quiz_ranking(text, text, integer) from public, anon;
grant execute on function public.list_quiz_ranking(text, text, integer) to authenticated;
