-- Keep the database membership approval gate aligned with the app's explicit
-- privilege model. The mobile app grants member-review access through the
-- approveMembers app privilege, while the original database helper only
-- accepted church_member_roles titles.

create or replace function public.can_manage_church_members(target_church_id text)
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  with actor as (
    select
      u.id,
      u.uid,
      coalesce(u."appPrivileges", '{}'::text[]) as app_privileges
    from public.users u
    where u.id = auth.uid()
       or u.uid = auth.uid()::text
    limit 1
  )
  select exists (
    select 1
    from actor a
    join public.church_memberships cm
      on cm.user_id = auth.uid()
    join public.churches c
      on c.id = cm.church_id
      or c."placeId" = cm.church_id
    left join public.church_member_roles cmr
      on cmr.membership_id = cm.id
     and cmr.revoked_at is null
    where cm.church_id = nullif(trim(coalesce(target_church_id, '')), '')
      and cm.membership_status = 'active'
      and c.church_status = 'approved'
      and c.public_visibility = true
      and (
        public.normalize_role_name(cmr.role_name) in (
          'pastor',
          'senior_pastor',
          'assistant_pastor',
          'acting_pastor',
          'church_admin',
          'admin',
          'administrator',
          'secretary',
          'church_secretary'
        )
        or exists (
          select 1
          from unnest(a.app_privileges) as privilege_name
          where trim(privilege_name) in (
            'approveMembers',
            'manageChurchSettings'
          )
        )
      )
  );
$$;

grant execute on function public.can_manage_church_members(text) to authenticated;
