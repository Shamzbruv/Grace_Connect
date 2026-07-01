-- Give church leaders enough identity detail to vet pending member requests
-- without opening broad user-table reads for pending/churchless accounts.

create or replace function public.list_church_membership_requests(
  p_church_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  clean_church_id text := nullif(trim(coalesce(p_church_id, '')), '');
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if clean_church_id is null then
    select nullif(trim("placeId"), '')
      into clean_church_id
    from public.users
    where id = actor_id or uid = actor_id::text
    limit 1;
  end if;

  if clean_church_id is null then
    raise exception 'Church id is required.';
  end if;

  if not public.can_manage_church_members(clean_church_id) then
    raise exception 'You cannot manage members for this church.';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        cm.id::text as id,
        cm.user_id::text as user_id,
        cm.church_id,
        cm.request_message,
        cm.requested_at,
        jsonb_build_object(
          'id', coalesce(u.id::text, au.id::text, cm.user_id::text),
          'uid', coalesce(u.uid, au.id::text, cm.user_id::text),
          'fullName', coalesce(
            nullif(u."fullName", ''),
            nullif(au.raw_user_meta_data->>'full_name', ''),
            nullif(au.raw_user_meta_data->>'fullName', ''),
            nullif(au.raw_user_meta_data->>'name', '')
          ),
          'displayName', coalesce(
            nullif(u."fullName", ''),
            nullif(au.raw_user_meta_data->>'full_name', ''),
            nullif(au.raw_user_meta_data->>'name', '')
          ),
          'email', coalesce(nullif(u.email, ''), au.email),
          'phone', coalesce(
            nullif(u.phone, ''),
            nullif(au.phone, ''),
            nullif(au.raw_user_meta_data->>'phone', ''),
            nullif(au.raw_user_meta_data->>'phoneNumber', '')
          ),
          'photoUrl', coalesce(nullif(u."photoUrl", ''), nullif(au.raw_user_meta_data->>'avatar_url', '')),
          'accountState', coalesce(nullif(u."accountState", ''), 'pending'),
          'joinDate', coalesce(u."joinDate", au.created_at),
          'dateOfBirth', u."dateOfBirth",
          'gender', u.gender,
          'occupation', u.occupation,
          'profileComplete', (
            nullif(coalesce(u."fullName", au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name'), '') is not null
            and nullif(coalesce(u.email, au.email), '') is not null
            and nullif(coalesce(u.phone, au.phone, au.raw_user_meta_data->>'phone', au.raw_user_meta_data->>'phoneNumber'), '') is not null
          )
        ) as profile
      from public.church_memberships cm
      left join public.users u on u.id = cm.user_id or u.uid = cm.user_id::text
      left join auth.users au on au.id = cm.user_id
      where cm.church_id = clean_church_id
        and cm.membership_status = 'pending'
      order by cm.requested_at asc
    ) r
  );
end;
$$;

grant execute on function public.list_church_membership_requests(text) to authenticated;
