-- Legacy churches that were already active before the new approval workflow
-- should remain joinable from the landing member signup search.

update public.churches
set church_status = 'approved',
    public_visibility = true,
    approved_at = coalesce(approved_at, now()),
    updated_at = now()
where coalesce(status, '') in ('active', 'verified')
  and (
    coalesce(church_status, '') <> 'approved'
    or public_visibility is distinct from true
  );

create or replace function public.get_public_church_directory(search_query text default null)
returns table (
  id text,
  "placeId" text,
  name text,
  address text,
  parish text,
  denomination text
)
language sql
security definer
set search_path to 'public'
as $$
  select
    coalesce(c.id, c."placeId")::text as id,
    coalesce(c."placeId", c.id)::text as "placeId",
    coalesce(nullif(c.display_name, ''), nullif(c.name, ''), c."placeId", c.id::text)::text as name,
    coalesce(c.address, '')::text as address,
    coalesce(c.parish, '')::text as parish,
    coalesce(c.denomination_label, c.denomination, '')::text as denomination
  from public.churches c
  where (
      (c.church_status = 'approved' and coalesce(c.public_visibility, true) = true)
      or coalesce(c.status, '') in ('active', 'verified')
    )
    and (
      nullif(trim(coalesce(search_query, '')), '') is null
      or coalesce(c.display_name, c.name, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c."placeId", '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.address, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.parish, '') ilike '%' || trim(search_query) || '%'
      or coalesce(c.denomination_label, c.denomination, '') ilike '%' || trim(search_query) || '%'
    )
  order by name;
$$;

grant execute on function public.get_public_church_directory(text) to anon, authenticated;
