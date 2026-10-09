-- Per-person reactions stay private; only published quote totals are public.
create table private.daily_motivation_likes (
 motivation_id uuid not null references public.daily_motivations(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key(motivation_id,user_id)
);
create index daily_motivation_likes_user_idx on private.daily_motivation_likes(user_id);
create table private.daily_motivation_like_counts (
 motivation_id uuid primary key references public.daily_motivations(id) on delete cascade,
 like_count bigint not null default 0 check(like_count>=0)
);
alter table private.daily_motivation_likes enable row level security;
alter table private.daily_motivation_like_counts enable row level security;
revoke all on private.daily_motivation_likes,private.daily_motivation_like_counts from public,anon,authenticated;

create function private.count_daily_motivation_like()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  insert into private.daily_motivation_like_counts(motivation_id,like_count) values(new.motivation_id,1)
  on conflict(motivation_id) do update set like_count=private.daily_motivation_like_counts.like_count+1;
 else
  update private.daily_motivation_like_counts set like_count=greatest(0,like_count-1) where motivation_id=old.motivation_id;
 end if;
 return null;
end;$$;
revoke all on function private.count_daily_motivation_like() from public,anon,authenticated;
create trigger daily_motivation_like_counter after insert or delete on private.daily_motivation_likes
for each row execute function private.count_daily_motivation_like();

create function public.get_daily_motivation_engagement(p_motivation_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('motivation_id',q.id,'like_count',coalesce(c.like_count,0),'liked',
  exists(select 1 from private.daily_motivation_likes l where l.motivation_id=q.id and l.user_id=(select auth.uid())))
 from public.daily_motivations q left join private.daily_motivation_like_counts c on c.motivation_id=q.id
 where q.id=p_motivation_id and q.is_published and q.status='published'
 and q.publish_date <= (now() at time zone 'America/Jamaica')::date;
$$;
revoke all on function public.get_daily_motivation_engagement(uuid) from public;
grant execute on function public.get_daily_motivation_engagement(uuid) to anon,authenticated;

create function public.set_daily_motivation_like(p_motivation_id uuid,p_liked boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();phase text;
begin
 if actor is null or not exists(select 1 from auth.users where id=actor) then
  raise exception 'Sign in to like this Daily Word.' using errcode='42501';
 end if;
 if p_liked is null then raise exception 'Choose like or unlike.' using errcode='22023';end if;
 -- Coordinate with reset-start without stopping internal FK cleanup cascades.
 select c.phase into phase from private.platform_reset_control c where singleton for share;
 if phase not in ('idle','complete') or phase is null then
  raise exception 'Grace Connect is being reset. Please try again shortly.' using errcode='55000';
 end if;
 perform 1 from public.daily_motivations q where q.id=p_motivation_id and q.is_published and q.status='published'
  and q.publish_date <= (now() at time zone 'America/Jamaica')::date for share;
 if not found then raise exception 'This Daily Word is no longer available.' using errcode='42501';end if;
 if p_liked then
  insert into private.daily_motivation_likes(motivation_id,user_id) values(p_motivation_id,actor) on conflict do nothing;
 else
  delete from private.daily_motivation_likes where motivation_id=p_motivation_id and user_id=actor;
 end if;
 return public.get_daily_motivation_engagement(p_motivation_id);
end;$$;
revoke all on function public.set_daily_motivation_like(uuid,boolean) from public,anon;
grant execute on function public.set_daily_motivation_like(uuid,boolean) to authenticated;

-- The phone widget can refresh this system-authored, published global content
-- with a publishable key. No user names, reaction identities or drafts leak.
create function public.get_daily_word_widget()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',q.id,'publish_date',q.publish_date,'title',left(q.title,160),
  'message',left(q.message,1800),'scripture_reference',left(q.scripture_reference,160),
  'like_count',coalesce(c.like_count,0))
 from public.daily_motivations q left join private.daily_motivation_like_counts c on c.motivation_id=q.id
 where q.is_published and q.status='published' and q.publish_date <= (now() at time zone 'America/Jamaica')::date
 order by q.publish_date desc limit 1;
$$;
revoke all on function public.get_daily_word_widget() from public;
grant execute on function public.get_daily_word_widget() to anon,authenticated;

comment on table private.daily_motivation_likes is
 'Reactions cascade when quotes/accounts are removed, including retention and the protected reset. They must not make unrelated accounts reset-preservation roots.';
