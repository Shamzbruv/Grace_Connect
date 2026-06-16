-- Global feed search helpers and exact post notification routing.

create or replace function public.search_people_global(
  search_query text,
  result_limit integer default 30
)
returns setof public.users
language sql
security definer
set search_path = public
as $$
  select u.*
  from public.users u
  where auth.uid() is not null
    and length(trim(coalesce(search_query, ''))) >= 2
    and coalesce(u."accountState", 'active') <> 'disabled'
    and (
      u."fullName" ilike ('%' || trim(search_query) || '%')
      or u.email ilike ('%' || trim(search_query) || '%')
      or coalesce(u."placeName", '') ilike ('%' || trim(search_query) || '%')
    )
  order by
    case
      when lower(u."fullName") = lower(trim(search_query)) then 0
      when lower(u."fullName") like lower(trim(search_query)) || '%' then 1
      else 2
    end,
    u."fullName"
  limit least(greatest(coalesce(result_limit, 30), 1), 50);
$$;

grant execute on function public.search_people_global(text, integer)
  to authenticated;

create or replace function public.notify_on_community_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_author uuid;
  target_place_id text;
begin
  select author_id, place_id
    into target_author, target_place_id
    from public.community_posts
    where id = new.post_id;

  if target_author is null or target_author = new.author_id then
    return new;
  end if;

  perform public.create_notification(
    target_author,
    new.author_id,
    'comment',
    'New comment',
    coalesce(public.display_name_for_user(new.author_id), 'Someone') ||
      ' commented on your post.',
    target_place_id,
    'community_posts',
    new.post_id::text,
    '/community'
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_on_community_comment
  on public.community_comments;
create trigger trg_notify_on_community_comment
  after insert on public.community_comments
  for each row execute function public.notify_on_community_comment();
