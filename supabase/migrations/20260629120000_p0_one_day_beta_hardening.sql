-- P0 one-day beta hardening.
-- Keep this forward-only: do not edit the earlier Round 7 migration after it may
-- already have been applied to a live Supabase project.

-- Round 7 introduced alternate church-registration column names and a void
-- overload. The table created earlier uses the *_submitted / pastor_* contract,
-- so keep one canonical RPC that writes those columns.
alter table public.church_registration_requests
  add column if not exists applicant_note text;

drop function if exists public.submit_church_registration(
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  uuid
);

drop function if exists public.submit_church_registration(
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  text
);

create function public.submit_church_registration(
  church_name text,
  location text default null,
  church_address text default null,
  church_parish text default null,
  denomination uuid default null,
  custom_denomination text default null,
  pastor_full_name text default null,
  pastor_contact_email text default null,
  pastor_contact_phone text default null,
  legal_acceptance uuid default null,
  applicant_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  actor_email text := auth.jwt()->>'email';
  is_email_confirmed boolean;
  inserted_id uuid;
  denom_code text;
  denom_record record;
  final_church_name text;
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  select (email_confirmed_at is not null)
    into is_email_confirmed
  from auth.users
  where id = actor_id;

  if is_email_confirmed is not true then
    raise exception 'Email must be confirmed before submitting registration.';
  end if;

  if lower(trim(coalesce(pastor_contact_email, ''))) is distinct from lower(trim(coalesce(actor_email, ''))) then
    raise exception 'Pastor contact email must match your verified account email.';
  end if;

  perform public.require_current_policy_acceptances(actor_id, 'church_application');

  if legal_acceptance is null then
    raise exception 'A church registration authority declaration acceptance ID is required.';
  end if;

  if not exists (
    select 1
    from public.policy_acceptances pa
    join public.policy_documents pd
      on pd.document_key = pa.document_key
     and pd.document_version = pa.document_version
    where pa.id = legal_acceptance
      and pa.user_id = actor_id
      and pa.document_key = 'church_registration_authority'
      and pd.is_active = true
  ) then
    raise exception 'Invalid church_registration_authority acceptance reference.';
  end if;

  if nullif(trim(coalesce(church_name, '')), '') is null then
    raise exception 'Church name is required.';
  end if;
  final_church_name := trim(church_name);

  if nullif(trim(coalesce(church_parish, '')), '') is null then
    raise exception 'Parish is required.';
  end if;

  if nullif(trim(coalesce(church_address, '')), '') is null then
    raise exception 'Church address is required.';
  end if;

  if denomination is null then
    raise exception 'Denomination selection is required.';
  end if;

  select *
    into denom_record
  from public.denominations
  where id = denomination
    and is_active = true;

  if denom_record.id is null then
    raise exception 'Invalid or inactive denomination.';
  end if;

  denom_code := denom_record.code;

  if denom_code <> 'other' and nullif(trim(coalesce(custom_denomination, '')), '') is not null then
    raise exception 'Custom denomination is only allowed when selecting "Other".';
  end if;

  if denom_code = 'other' and nullif(trim(coalesce(custom_denomination, '')), '') is null then
    raise exception 'Please specify your denomination when selecting "Other".';
  end if;

  if denom_code = 'ntcog' then
    if nullif(trim(coalesce(location, '')), '') is not null then
      final_church_name := trim(regexp_replace(location, '(?i)\s*(new testament church of god|ntcog)\s*', '', 'g')) || ' NTCOG';
    else
      final_church_name := trim(regexp_replace(final_church_name, '(?i)\s*(new testament church of god|ntcog)\s*', '', 'g')) || ' NTCOG';
    end if;
  end if;

  select id
    into inserted_id
  from public.church_registration_requests
  where requested_by_user_id = actor_id
    and application_status in (
      'submitted',
      'under_review',
      'needs_information'
    )
  order by created_at desc
  limit 1;

  if inserted_id is not null then
    return inserted_id;
  end if;

  insert into public.church_registration_requests (
    requested_by_user_id,
    church_name_submitted,
    location_name,
    address,
    parish,
    denomination_id,
    custom_denomination_name,
    pastor_name,
    pastor_email,
    pastor_phone,
    legal_acceptance_id,
    applicant_note
  )
  values (
    actor_id,
    final_church_name,
    nullif(trim(coalesce(location, '')), ''),
    nullif(trim(coalesce(church_address, '')), ''),
    nullif(trim(coalesce(church_parish, '')), ''),
    denomination,
    nullif(trim(coalesce(custom_denomination, '')), ''),
    nullif(trim(coalesce(pastor_full_name, '')), ''),
    nullif(trim(coalesce(pastor_contact_email, '')), ''),
    nullif(trim(coalesce(pastor_contact_phone, '')), ''),
    legal_acceptance,
    nullif(trim(coalesce(applicant_note, '')), '')
  )
  returning id into inserted_id;

  insert into public.church_approval_audit_events (
    actor_user_id,
    target_user_id,
    event_type,
    details
  )
  values (
    actor_id,
    actor_id,
    'church_registration_submitted',
    jsonb_build_object('requestId', inserted_id, 'churchName', final_church_name)
  );

  return inserted_id;
end;
$$;

grant execute on function public.submit_church_registration(
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  text,
  uuid,
  text
) to authenticated;

-- Remove Round 7 developer overloads that reference non-existent registration
-- columns. Keep the canonical developer_list_churches(text, text) and
-- approve_church_registration(uuid, text) functions from the membership
-- foundation/developer portal migrations.
drop function if exists public.developer_list_churches(text);
drop function if exists public.developer_approve_church(uuid, uuid);

-- The finalizer Edge Function now accepts only ATTENDANCE_CRON_SECRET. Reschedule
-- the database cron to use the matching vault secret instead of the quiz secret.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'service-attendance-finalizer') then
    perform cron.unschedule('service-attendance-finalizer');
  end if;
end $$;

select cron.schedule(
  'service-attendance-finalizer',
  '*/15 * * * *',
  $cron$
  select net.http_post(
    url := coalesce(
      (select decrypted_secret from vault.decrypted_secrets where name = 'grace_connect_project_url' limit 1),
      'https://nimgsgnkcvddomrgkawb.supabase.co'
    ) || '/functions/v1/finalize-service-attendance',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', coalesce(
        (select decrypted_secret from vault.decrypted_secrets where name = 'attendance_cron_secret' limit 1),
        ''
      )
    ),
    body := '{}'::jsonb
  );
  $cron$
);
