-- Church profile: logo and the pastor currently leading the church.
--
-- The profile already carried about/founded year/contact/website. What a
-- member actually looks for first -- the church's picture and who leads it --
-- had nowhere to live.

alter table public.churches
  add column if not exists logo_url text,
  add column if not exists managing_pastor_name text,
  add column if not exists managing_pastor_title text,
  -- "at the time" matters: leadership changes, and a profile that silently
  -- rewrites history is worse than one that says when someone took over.
  add column if not exists managing_pastor_since date;

-- Logos live with the other public profile imagery. The bucket is already
-- public and already holds avatars; a church logo is the same kind of asset,
-- so this reuses it rather than adding another bucket to secure.
insert into storage.buckets (id, name, public)
values ('church_media', 'church_media', true)
on conflict (id) do update set public = true;

drop policy if exists "Church media is publicly readable" on storage.objects;
create policy "Church media is publicly readable"
  on storage.objects for select
  using (bucket_id = 'church_media');

-- Only a leader of that church may write its imagery, and only under that
-- church's own prefix -- so one church cannot overwrite another's logo.
drop policy if exists "Church leaders manage their church media" on storage.objects;
create policy "Church leaders manage their church media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'church_media'
    and (storage.foldername(name))[1] = public.get_church_id()
    and public.has_any_role(array['Pastor','Senior Pastor','Secretary','Admin'])
  );

drop policy if exists "Church leaders replace their church media" on storage.objects;
create policy "Church leaders replace their church media"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'church_media'
    and (storage.foldername(name))[1] = public.get_church_id()
    and public.has_any_role(array['Pastor','Senior Pastor','Secretary','Admin'])
  );

drop policy if exists "Church leaders remove their church media" on storage.objects;
create policy "Church leaders remove their church media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'church_media'
    and (storage.foldername(name))[1] = public.get_church_id()
    and public.has_any_role(array['Pastor','Senior Pastor','Secretary','Admin'])
  );

-- Extend the profile update to carry the new fields. Added as new trailing
-- parameters with defaults so existing callers keep working unchanged.
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
      timezone = coalesce(nullif(trim(p_timezone), ''), timezone, 'America/Jamaica'),
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
      managing_pastor_name = nullif(trim(coalesce(p_managing_pastor_name, '')), ''),
      managing_pastor_title = nullif(trim(coalesce(p_managing_pastor_title, '')), ''),
      managing_pastor_since = p_managing_pastor_since,
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
