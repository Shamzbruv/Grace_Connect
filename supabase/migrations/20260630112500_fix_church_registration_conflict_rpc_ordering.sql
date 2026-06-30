-- Finish the public registration conflict RPC repair by ranking matches before
-- aggregating them into JSON. This avoids aggregate/order-by grouping errors.

create or replace function public.check_church_registration_conflicts(
  church_name text,
  location_name text default null,
  address text default null,
  parish text default null,
  denomination_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  p_church_name text := church_name;
  p_location_name text := location_name;
  p_address text := address;
  p_parish text := parish;
  p_denomination_id text := denomination_id;
  normalized_name text := lower(regexp_replace(coalesce(p_church_name, ''), '[^a-z0-9]+', '', 'g'));
  normalized_location text := lower(regexp_replace(coalesce(p_location_name, ''), '[^a-z0-9]+', '', 'g'));
  normalized_address text := lower(regexp_replace(coalesce(p_address, ''), '[^a-z0-9]+', '', 'g'));
  match_count integer;
  safe_matches jsonb;
begin
  with scored as (
    select candidate.*,
      case
        when lower(regexp_replace(coalesce(candidate.display_name, candidate.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name
          and nullif(p_parish, '') is not null
          and lower(coalesce(candidate.parish, '')) = lower(p_parish)
          then 100
        when lower(regexp_replace(coalesce(candidate.display_name, candidate.name, ''), '[^a-z0-9]+', '', 'g')) = normalized_name
          and nullif(normalized_address, '') is not null
          and lower(regexp_replace(coalesce(candidate.address, ''), '[^a-z0-9]+', '', 'g')) = normalized_address
          then 100
        when normalized_location <> ''
          and lower(regexp_replace(coalesce(candidate.location_name, ''), '[^a-z0-9]+', '', 'g')) = normalized_location
          and (p_denomination_id is null or candidate.denomination_id::text = p_denomination_id)
          and nullif(p_parish, '') is not null
          and lower(coalesce(candidate.parish, '')) = lower(p_parish)
          then 100
        when lower(regexp_replace(coalesce(candidate.display_name, candidate.name, ''), '[^a-z0-9]+', '', 'g')) like '%' || normalized_name || '%'
          and nullif(p_parish, '') is not null
          and lower(coalesce(candidate.parish, '')) = lower(p_parish)
          then 50
        when normalized_address <> ''
          and lower(regexp_replace(coalesce(candidate.address, ''), '[^a-z0-9]+', '', 'g')) like '%' || normalized_address || '%'
          and (p_denomination_id is null or candidate.denomination_id::text = p_denomination_id)
          then 50
        else 0
      end as match_score
    from public.churches candidate
    where normalized_name <> ''
  ),
  ranked as (
    select *
    from scored
    where match_score >= 50
    order by match_score desc, "createdAt" desc nulls last
    limit 5
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', coalesce(nullif(ranked.display_name, ''), nullif(ranked.name, ''), 'Possible match'),
    'address', ranked.address,
    'parish', ranked.parish,
    'status', case when ranked.church_status = 'approved' then 'registered' else 'under_review' end
  ) order by ranked.match_score desc, ranked."createdAt" desc nulls last), '[]'::jsonb)
    into safe_matches
    from ranked;

  match_count := jsonb_array_length(safe_matches);

  return jsonb_build_object(
    'has_conflict', match_count > 0,
    'match_count', match_count,
    'safe_message', case
      when match_count > 0 then 'This church may already be registered on Grace Connect.'
      else 'No likely registration conflict found.'
    end,
    'matches', safe_matches
  );
end;
$$;

grant execute on function public.check_church_registration_conflicts(text, text, text, text, text)
  to anon, authenticated;
