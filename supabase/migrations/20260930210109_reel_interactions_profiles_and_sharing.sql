-- Repair installed clients as well as new ones: identity defaults still pass RLS.
alter table public.reel_likes alter column user_id set default auth.uid()::text;
alter table public.reel_comments alter column author_id set default auth.uid()::text;
alter table public.reel_user_feedback alter column user_id set default auth.uid()::text;
alter table public.social_saved_items alter column user_id set default auth.uid()::text;

-- Policies execute as the requesting role. Do not expose the private schema.
create or replace function public.can_read_reel(p_reel_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select auth.uid() is not null and private.can_view_reel(auth.uid(), p_reel_id) $$;
revoke all on function public.can_read_reel(uuid) from public, anon;
grant execute on function public.can_read_reel(uuid) to authenticated;

do $$
declare pol record;
begin
  for pol in select * from pg_policies
    where schemaname = 'public' and tablename in ('reels','reel_likes','reel_comments')
  loop
    if pol.qual like '%private.can_view_reel%' then
      execute format('alter policy %I on public.%I using (%s)', pol.policyname, pol.tablename,
        replace(pol.qual, 'private.can_view_reel(( SELECT auth.uid() AS uid),', 'public.can_read_reel('));
    end if;
    if pol.with_check like '%private.can_view_reel%' then
      execute format('alter policy %I on public.%I with check (%s)', pol.policyname, pol.tablename,
        replace(pol.with_check, 'private.can_view_reel(( SELECT auth.uid() AS uid),', 'public.can_read_reel('));
    end if;
  end loop;
end $$;

-- Clients cannot publish unverified uploads, modify counts or override moderation.
revoke all on public.reels, public.reel_likes, public.reel_comments,
  public.reel_user_feedback from anon, authenticated;
grant select on public.reels to authenticated;
grant update (caption, category, comments_enabled, visibility) on public.reels to authenticated;
grant select, insert, delete on public.reel_likes, public.reel_user_feedback to authenticated;
grant select, insert, delete on public.reel_comments to authenticated;
grant update (body) on public.reel_comments to authenticated;

create or replace function private.validate_reel_comment()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.parent_comment_id is not null and not exists (
    select 1 from public.reel_comments p
    where p.id = new.parent_comment_id and p.reel_id = new.reel_id and p.status = 'active'
  ) then raise exception 'The reply must belong to this reel.' using errcode = '23514'; end if;
  return new;
end $$;
revoke all on function private.validate_reel_comment() from public, anon, authenticated;
create trigger validate_reel_comment before insert or update on public.reel_comments
for each row execute function private.validate_reel_comment();

-- Atomic increments serialize on the reel row and never overwrite another writer.
create or replace function private.update_reel_engagement()
returns trigger language plpgsql security definer set search_path = '' as $$
declare target uuid; delta integer;
begin
  if tg_table_name = 'social_saved_items' then
    if tg_op = 'INSERT' then
      if new.entity_type <> 'reel' then return null; end if;
      target := new.entity_id::uuid; delta := 1;
    else
      if old.entity_type <> 'reel' then return null; end if;
      target := old.entity_id::uuid; delta := -1;
    end if;
    update public.reels set save_count = greatest(0, save_count + delta) where id = target;
  elsif tg_table_name = 'reel_likes' then
    if tg_op = 'INSERT' then target := new.reel_id; delta := 1;
    else target := old.reel_id; delta := -1; end if;
    update public.reels set like_count = greatest(0, like_count + delta) where id = target;
  else
    if tg_op = 'INSERT' then
      target := new.reel_id; delta := case when new.status = 'active' then 1 else 0 end;
    elsif tg_op = 'DELETE' then
      target := old.reel_id; delta := case when old.status = 'active' then -1 else 0 end;
    else
      target := new.reel_id;
      delta := (case when new.status = 'active' then 1 else 0 end)
             - (case when old.status = 'active' then 1 else 0 end);
    end if;
    update public.reels set comment_count = greatest(0, comment_count + delta) where id = target;
  end if;
  return null;
end $$;
revoke all on function private.update_reel_engagement() from public, anon, authenticated;
create trigger reel_like_count after insert or delete on public.reel_likes
for each row execute function private.update_reel_engagement();
create trigger reel_comment_count after insert or update or delete on public.reel_comments
for each row execute function private.update_reel_engagement();
create trigger reel_save_count after insert or delete on public.social_saved_items
for each row execute function private.update_reel_engagement();

update public.reels r set
  like_count = (select count(*) from public.reel_likes l where l.reel_id=r.id),
  comment_count = (select count(*) from public.reel_comments c where c.reel_id=r.id and c.status='active'),
  save_count = (select count(*) from public.social_saved_items s where s.entity_type='reel' and s.entity_id=r.id::text);

create or replace function private.reel_card(p_id uuid, p_actor uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id',r.id,'author_id',r.author_id,'author_name',coalesce(nullif(u."displayName",''),nullif(u."fullName",''),'Member'),
    'author_avatar_url',u."photoUrl",'author_church_id',r.author_church_id,
    'caption',r.caption,'visibility',r.visibility,'category',r.category,
    'duration_ms',r.duration_ms,'aspect_ratio',r.aspect_ratio,'audio_label',r.audio_label,
    'comments_enabled',r.comments_enabled,'published_at',r.published_at,
    'like_count',r.like_count,'comment_count',r.comment_count,'save_count',r.save_count,
    'viewer_liked',exists(select 1 from public.reel_likes where reel_id=r.id and user_id=p_actor::text),
    'viewer_saved',exists(select 1 from public.social_saved_items where entity_type='reel' and entity_id=r.id::text and user_id=p_actor::text)
  )
  from public.reels r
  left join lateral (select "displayName","fullName","photoUrl" from public.users
    where uid=r.author_id or id::text=r.author_id order by (uid=r.author_id) desc limit 1) u on true
  where r.id=p_id and private.can_view_reel(p_actor,r.id)
    and r.status='ready' and r.moderation_status='approved' and r.deleted_at is null
$$;
revoke all on function private.reel_card(uuid,uuid) from public, anon, authenticated;

create or replace function public.get_reel_grace_detail(p_reel_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is not null then private.reel_card(p_reel_id,auth.uid()) end
$$;
revoke all on function public.get_reel_grace_detail(uuid) from public, anon;
grant execute on function public.get_reel_grace_detail(uuid) to authenticated;

create or replace function public.get_reel_grace_profile(p_author_id text, p_cursor jsonb default null, p_limit integer default 12)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := auth.uid(); items jsonb; capped integer := greatest(1,least(coalesce(p_limit,12),20));
begin
  if actor is null then raise exception 'Sign in to view reels.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(private.reel_card(r.id,actor) order by r.published_at desc,r.id desc),'[]'::jsonb)
  into items from (
    select * from public.reels r where r.author_id=p_author_id and r.status='ready'
    and r.moderation_status='approved' and r.deleted_at is null and r.published_at is not null
    and private.can_view_reel(actor,r.id)
    and (p_cursor is null or (r.published_at,r.id) < ((p_cursor->>'published_at')::timestamptz,(p_cursor->>'id')::uuid))
    order by r.published_at desc,r.id desc limit capped
  ) r;
  return jsonb_build_object('reels',items,'next_cursor',case when jsonb_array_length(items)=capped
    then jsonb_build_object('published_at',items->-1->>'published_at','id',items->-1->>'id') end);
end $$;
revoke all on function public.get_reel_grace_profile(text,jsonb,integer) from public, anon;
grant execute on function public.get_reel_grace_profile(text,jsonb,integer) to authenticated;
