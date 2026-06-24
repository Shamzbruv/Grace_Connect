-- 1. Remove metadata-driven operations from handle_new_auth_user
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  profile_phone text := nullif(coalesce(meta->>'phone', meta->>'phoneNumber'), '');
begin
  insert into public.users (
    id,
    uid,
    email,
    "fullName",
    phone,
    "placeId",
    "placeName",
    roles,
    "joinDate",
    "photoUrl",
    bio,
    "isDeveloper",
    "accountState"
  )
  values (
    new.id,
    new.id::text,
    coalesce(new.email, ''),
    coalesce(
      nullif(meta->>'fullName', ''),
      nullif(meta->>'full_name', ''),
      nullif(meta->>'name', ''),
      split_part(coalesce(new.email, 'Member'), '@', 1)
    ),
    profile_phone,
    null,
    null,
    array['Member'],
    now(),
    coalesce(nullif(meta->>'avatar_url', ''), ''),
    coalesce(nullif(meta->>'bio', ''), ''),
    false,
    'active'
  )
  on conflict (uid) do update
    set email = excluded.email,
        "fullName" = coalesce(nullif(excluded."fullName", ''), public.users."fullName"),
        phone = coalesce(excluded.phone, public.users.phone),
        roles = case
          when public.users.roles is null or array_length(public.users.roles, 1) is null then array['Member']
          else public.users.roles
        end;
        
  -- Removed all implicit side-effects (policy_acceptances, church_registration_requests, church_memberships)
  return new;
end;
$$;

-- 2. Define get_active_denominations RPC
create or replace function public.get_active_denominations()
returns setof public.denominations
language sql
security definer
set search_path = public
as $$
  select * from public.denominations where is_active = true order by display_name asc;
$$;

grant execute on function public.get_active_denominations() to authenticated;
grant execute on function public.get_active_denominations() to anon;

-- 3. Secure church_registration_requests (Drop Insert Policy)
drop policy if exists "Users create own church registration requests" on public.church_registration_requests;

-- 4. Legacy Legal Acceptance Reconciliation
DO $$
DECLARE
  rec record;
  doc_key text;
  doc_ver text;
  acc_source text;
  ip_meta jsonb;
BEGIN
  -- Check if legacy table exists
  IF EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'user_legal_acceptances'
  ) THEN
    
    FOR rec IN SELECT * FROM public.user_legal_acceptances LOOP
      doc_ver := coalesce(rec.document_version, 'legacy');
      acc_source := 'migration';
      ip_meta := '{}'::jsonb;
      
      BEGIN
        IF rec.acceptance_source IS NOT NULL THEN
          acc_source := rec.acceptance_source;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- Column acceptance_source doesn't exist, ignore
      END;

      BEGIN
        IF rec.source IS NOT NULL THEN
          acc_source := rec.source;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- Column source doesn't exist, ignore
      END;

      BEGIN
        IF rec.ip_or_device_metadata IS NOT NULL THEN
          ip_meta := rec.ip_or_device_metadata;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- Column ip_or_device_metadata doesn't exist, ignore
      END;

      -- Determine document key from legacy if present, else fallback
      doc_key := 'terms';
      BEGIN
        IF rec.document_key IS NOT NULL THEN
          doc_key := rec.document_key;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        -- Assume terms if not found
      END;

      -- Attempt insert
      BEGIN
        INSERT INTO public.policy_acceptances (
          user_id, document_key, document_version, accepted_at, source, ip_or_device_metadata
        ) VALUES (
          rec.user_id, doc_key, doc_ver, coalesce(rec.accepted_at, now()), acc_source, ip_meta
        ) ON CONFLICT (user_id, document_key) DO NOTHING;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Skipped record for user %', rec.user_id;
      END;
      
    END LOOP;
    
    -- Try to drop any old auth trigger that was failing on this table
    BEGIN
      DROP TRIGGER IF EXISTS on_auth_user_created_legal_accept ON auth.users;
    EXCEPTION WHEN OTHERS THEN
      -- Ignore
    END;
    
  END IF;
END $$;

