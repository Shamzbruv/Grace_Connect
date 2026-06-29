-- Developer portal + app support/reporting hardening.
-- Adds a Supabase-backed issue report flow, church profile metadata, church
-- drill-down RPCs, setup prompts, and email-notification queue rows.

alter table public.churches
  add column if not exists about text,
  add column if not exists founded_year integer,
  add column if not exists contact_email text,
  add column if not exists contact_phone text,
  add column if not exists website_url text,
  add column if not exists service_times_note text,
  add column if not exists profile_updated_at timestamptz;

update public.churches c
set church_status = 'approved',
    public_visibility = true,
    approved_at = coalesce(c.approved_at, now()),
    updated_at = now()
where coalesce(c.status, '') in ('active', 'verified')
  and (
    coalesce(c.church_status, '') <> 'approved'
    or c.public_visibility is distinct from true
  );

create table if not exists public.email_notification_queue (
  id uuid primary key default gen_random_uuid(),
  to_email text not null,
  subject text not null,
  html_body text not null,
  text_body text,
  status text not null default 'queued'
    check (status in ('queued', 'sent', 'failed', 'cancelled')),
  related_type text,
  related_id text,
  recipient_user_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  error_message text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists email_notification_queue_status_idx
  on public.email_notification_queue (status, created_at desc);

alter table public.email_notification_queue enable row level security;

drop policy if exists "email queue rpc only" on public.email_notification_queue;
create policy "email queue rpc only"
  on public.email_notification_queue
  for all
  using (false)
  with check (false);

create or replace function public.queue_app_email(
  p_to_email text,
  p_subject text,
  p_html_body text,
  p_text_body text default null,
  p_related_type text default null,
  p_related_id text default null,
  p_recipient_user_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  inserted_id uuid;
begin
  if nullif(trim(coalesce(p_to_email, '')), '') is null then
    return null;
  end if;

  insert into public.email_notification_queue (
    to_email,
    subject,
    html_body,
    text_body,
    related_type,
    related_id,
    recipient_user_id,
    metadata
  )
  values (
    lower(trim(p_to_email)),
    trim(coalesce(p_subject, 'Grace Connect update')),
    coalesce(p_html_body, ''),
    p_text_body,
    p_related_type,
    p_related_id,
    p_recipient_user_id,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into inserted_id;

  return inserted_id;
end;
$$;

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  "ticketId" text unique not null default replace(gen_random_uuid()::text, '-', ''),
  "userId" text,
  uid text,
  "reporterEmail" text not null,
  "churchId" text,
  roles text[] not null default '{}'::text[],
  "issueType" text not null default 'Bug / Something isn''t working',
  "appSection" text not null default 'Other',
  title text,
  subject text,
  summary text not null,
  description text not null,
  impact text not null default 'Medium',
  priority text not null default 'medium',
  "deviceInfo" jsonb not null default '{}'::jsonb,
  "attachmentUrls" text[] not null default '{}'::text[],
  status text not null default 'open'
    check (status in ('open', 'acknowledged', 'in_review', 'resolved', 'closed')),
  developer_notes text,
  acknowledged_by uuid,
  acknowledged_at timestamptz,
  resolved_by uuid,
  resolved_at timestamptz,
  "createdAt" timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_tickets_status_idx
  on public.support_tickets (status, "createdAt" desc);

create index if not exists support_tickets_church_idx
  on public.support_tickets ("churchId", status);

create or replace function public.touch_support_tickets_updated_at()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists support_tickets_touch_updated_at on public.support_tickets;
create trigger support_tickets_touch_updated_at
  before update on public.support_tickets
  for each row execute function public.touch_support_tickets_updated_at();

alter table public.support_tickets enable row level security;

drop policy if exists "Users create own support tickets" on public.support_tickets;
create policy "Users create own support tickets"
  on public.support_tickets
  for insert
  to authenticated
  with check (uid = auth.uid()::text or "userId" = auth.uid()::text);

drop policy if exists "Users view own support tickets" on public.support_tickets;
create policy "Users view own support tickets"
  on public.support_tickets
  for select
  to authenticated
  using (uid = auth.uid()::text or "userId" = auth.uid()::text);

drop policy if exists "Church staff view church support tickets" on public.support_tickets;
create policy "Church staff view church support tickets"
  on public.support_tickets
  for select
  to authenticated
  using (
    "churchId" is not null
    and public.can_manage_church_members("churchId")
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'support_attachments',
  'support_attachments',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']::text[]
)
on conflict (id) do update
  set public = true,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Users upload own support attachments" on storage.objects;
create policy "Users upload own support attachments"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'support_attachments'
    and (storage.foldername(name))[1] = 'support_tickets'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create or replace function public.submit_support_ticket(
  p_issue_type text,
  p_app_section text,
  p_summary text,
  p_description text,
  p_impact text default 'Medium',
  p_device_info jsonb default '{}'::jsonb,
  p_attachment_urls text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  actor_id uuid := auth.uid();
  profile record;
  ticket public.support_tickets;
  support_inbox text := 'shamzbiz1@gmail.com';
begin
  if actor_id is null then
    raise exception 'Not authenticated';
  end if;

  if nullif(trim(coalesce(p_summary, '')), '') is null then
    raise exception 'A short summary is required.';
  end if;

  if nullif(trim(coalesce(p_description, '')), '') is null then
    raise exception 'A description is required.';
  end if;

  select *
    into profile
  from public.users
  where id = actor_id or uid = actor_id::text
  limit 1;

  insert into public.support_tickets (
    "userId",
    uid,
    "reporterEmail",
    "churchId",
    roles,
    "issueType",
    "appSection",
    title,
    subject,
    summary,
    description,
    impact,
    priority,
    "deviceInfo",
    "attachmentUrls",
    status
  )
  values (
    actor_id::text,
    actor_id::text,
    coalesce(nullif(profile.email, ''), auth.jwt()->>'email', 'unknown'),
    nullif(coalesce(profile."placeId", public.get_church_id()), ''),
    coalesce(profile.roles, '{}'::text[]),
    nullif(trim(coalesce(p_issue_type, '')), ''),
    nullif(trim(coalesce(p_app_section, '')), ''),
    trim(p_summary),
    trim(p_summary),
    trim(p_summary),
    trim(p_description),
    coalesce(nullif(trim(p_impact), ''), 'Medium'),
    lower(coalesce(nullif(trim(p_impact), ''), 'medium')),
    coalesce(p_device_info, '{}'::jsonb),
    coalesce(p_attachment_urls, '{}'::text[]),
    'open'
  )
  returning * into ticket;

  perform public.queue_app_email(
    ticket."reporterEmail",
    'Grace Connect received your report',
    '<p>Thank you for reporting this issue to Grace Connect.</p><p>Your report <strong>' || ticket."ticketId" || '</strong> has been submitted and is now being reviewed. We will work with the church admin and, where needed, with you directly to resolve it.</p>',
    'Thank you for reporting this issue to Grace Connect. Your report ' || ticket."ticketId" || ' has been submitted and is now being reviewed.',
    'support_ticket',
    ticket.id::text,
    actor_id,
    jsonb_build_object('event', 'ticket_submitted')
  );

  perform public.queue_app_email(
    support_inbox,
    '[Grace Connect Issue] ' || ticket.summary,
    '<p><strong>Reporter:</strong> ' || coalesce(ticket."reporterEmail", 'unknown') || '</p><p><strong>Church:</strong> ' || coalesce(ticket."churchId", 'none') || '</p><p><strong>Section:</strong> ' || coalesce(ticket."appSection", 'Other') || '</p><p><strong>Impact:</strong> ' || coalesce(ticket.impact, 'Medium') || '</p><p>' || replace(ticket.description, E'\n', '<br>') || '</p>',
    ticket.description,
    'support_ticket',
    ticket.id::text,
    null,
    jsonb_build_object('event', 'developer_review_needed')
  );

  return jsonb_build_object(
    'ok', true,
    'id', ticket.id,
    'ticketId', ticket."ticketId",
    'status', ticket.status,
    'message', 'Your issue report was submitted and is now being reviewed.'
  );
end;
$$;

create or replace function public.developer_list_support_tickets(
  p_status text default null,
  p_search text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'support_developer', 'read_only_support', 'security_admin']);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        st.id::text,
        st."ticketId",
        st."reporterEmail",
        st."churchId",
        coalesce(c.display_name, c.name, st."churchId") as church_name,
        st."issueType",
        st."appSection",
        st.summary,
        st.description,
        st.impact,
        st.status,
        st.developer_notes,
        st."attachmentUrls",
        st."deviceInfo",
        st."createdAt",
        st.updated_at
      from public.support_tickets st
      left join public.churches c
        on c.id::text = st."churchId"
        or c."placeId"::text = st."churchId"
      where (
          nullif(trim(coalesce(p_status, '')), '') is null
          or lower(st.status) = lower(trim(p_status))
        )
        and (
          nullif(trim(coalesce(p_search, '')), '') is null
          or st.summary ilike '%' || trim(p_search) || '%'
          or st.description ilike '%' || trim(p_search) || '%'
          or st."reporterEmail" ilike '%' || trim(p_search) || '%'
          or coalesce(c.display_name, c.name, '') ilike '%' || trim(p_search) || '%'
        )
      order by
        case st.status when 'open' then 1 when 'acknowledged' then 2 when 'in_review' then 3 else 4 end,
        st."createdAt" desc
      limit 200
    ) r
  );
end;
$$;

create or replace function public.developer_update_support_ticket(
  p_ticket_id text,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  actor_id uuid := auth.uid();
  target public.support_tickets;
  normalized_status text := lower(trim(coalesce(p_status, 'acknowledged')));
begin
  select * into dev
  from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  if normalized_status not in ('acknowledged', 'in_review', 'resolved', 'closed') then
    raise exception 'Unsupported ticket status: %', normalized_status;
  end if;

  update public.support_tickets
  set status = normalized_status,
      developer_notes = nullif(trim(coalesce(p_note, '')), ''),
      acknowledged_by = case when acknowledged_by is null then actor_id else acknowledged_by end,
      acknowledged_at = case when acknowledged_at is null then now() else acknowledged_at end,
      resolved_by = case when normalized_status in ('resolved', 'closed') then actor_id else resolved_by end,
      resolved_at = case when normalized_status in ('resolved', 'closed') then now() else resolved_at end
  where id::text = p_ticket_id or "ticketId" = p_ticket_id
  returning * into target;

  if target.id is null then
    raise exception 'Issue report not found.';
  end if;

  perform public.queue_app_email(
    target."reporterEmail",
    'Grace Connect report update: ' || replace(normalized_status, '_', ' '),
    '<p>Your Grace Connect issue report <strong>' || target."ticketId" || '</strong> is now marked <strong>' || replace(normalized_status, '_', ' ') || '</strong>.</p><p>' || coalesce(nullif(trim(p_note), ''), 'Our team has reviewed the report and will continue working with the church admin where needed.') || '</p>',
    'Your Grace Connect issue report ' || target."ticketId" || ' is now marked ' || replace(normalized_status, '_', ' ') || '.',
    'support_ticket',
    target.id::text,
    null,
    jsonb_build_object('event', 'ticket_status_update', 'status', normalized_status, 'developer', dev.email)
  );

  perform public.log_developer_action(
    'support_ticket_' || normalized_status,
    'support_ticket',
    target.id::text,
    jsonb_build_object('ticketId', target."ticketId", 'note', nullif(trim(coalesce(p_note, '')), ''))
  );

  return to_jsonb(target);
end;
$$;

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

create or replace function public.update_church_profile(
  p_church_id text,
  p_name text,
  p_address text,
  p_denomination text,
  p_timezone text,
  p_about text default null,
  p_founded_year integer default null,
  p_contact_email text default null,
  p_contact_phone text default null,
  p_website_url text default null,
  p_service_times_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
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
        when p_founded_year is not null and p_founded_year between 1500 and extract(year from now())::integer then p_founded_year
        else null
      end,
      contact_email = nullif(trim(coalesce(p_contact_email, '')), ''),
      contact_phone = nullif(trim(coalesce(p_contact_phone, '')), ''),
      website_url = nullif(trim(coalesce(p_website_url, '')), ''),
      service_times_note = nullif(trim(coalesce(p_service_times_note, '')), ''),
      profile_updated_at = now(),
      updated_at = now()
  where id::text = target_church_id or "placeId"::text = target_church_id
  returning * into updated;

  if updated.id is null then
    raise exception 'Church not found.';
  end if;

  return to_jsonb(updated);
end;
$$;

create or replace function public.developer_get_church_detail(p_church_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
  members jsonb;
begin
  select * into dev from public.require_developer(null);

  select *
    into target
  from public.churches c
  where c.id::text = p_church_id or c."placeId"::text = p_church_id
  limit 1;

  if target.id is null then
    raise exception 'Church not found.';
  end if;

  select coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb)
    into members
  from (
    select
      cm.id::text as membership_id,
      cm.membership_status,
      cm.requested_at,
      cm.reviewed_at,
      u.id::text as user_id,
      u.email,
      u."fullName" as full_name,
      u.phone,
      u.roles,
      u."accountState" as account_state
    from public.church_memberships cm
    left join public.users u on u.id = cm.user_id or u.uid = cm.user_id::text
    where cm.church_id in (target.id::text, target."placeId"::text)
    order by
      case cm.membership_status when 'active' then 1 when 'pending' then 2 else 3 end,
      coalesce(u."fullName", u.email, '') asc
  ) m;

  return jsonb_build_object(
    'church', to_jsonb(target),
    'members', members
  );
end;
$$;

create or replace function public.developer_list_church_registration_requests(
  p_status text default null,
  p_search text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin', 'read_only_support']);

  return (
    select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
    from (
      select
        crr.id::text as id,
        crr.church_name_submitted as name,
        crr.location_name,
        crr.address,
        crr.parish,
        coalesce(d.display_name, crr.custom_denomination_name) as denomination,
        crr.pastor_name,
        case when dev.developer_role in ('super_developer', 'security_admin') then crr.pastor_email
             when crr.pastor_email is not null and position('@' in crr.pastor_email) > 0 then substr(crr.pastor_email, 1, 3) || '***@' || split_part(crr.pastor_email, '@', 2)
             else crr.pastor_email end as pastor_email,
        case when dev.developer_role in ('super_developer', 'security_admin') then crr.pastor_phone
             when crr.pastor_phone is not null and length(crr.pastor_phone) >= 4 then '***-***-' || right(crr.pastor_phone, 4)
             else crr.pastor_phone end as pastor_phone,
        crr.application_status as status,
        crr.review_notes,
        crr.applicant_note,
        crr.requested_by_user_id::text as requested_by_user_id,
        crr.created_at,
        crr.updated_at
      from public.church_registration_requests crr
      left join public.denominations d on d.id = crr.denomination_id
      where (
          nullif(trim(coalesce(p_status, '')), '') is null
          or lower(crr.application_status) = lower(trim(p_status))
          or (lower(trim(p_status)) = 'pending' and crr.application_status in ('submitted', 'under_review', 'needs_information'))
        )
        and (
          nullif(trim(coalesce(p_search, '')), '') is null
          or crr.church_name_submitted ilike '%' || trim(p_search) || '%'
          or coalesce(crr.address, '') ilike '%' || trim(p_search) || '%'
          or coalesce(crr.pastor_email, '') ilike '%' || trim(p_search) || '%'
        )
      order by crr.created_at desc
      limit 200
    ) r
  );
end;
$$;

create or replace function public.developer_send_church_setup_prompt(
  p_church_id text,
  p_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  target record;
  owner record;
  recipient text;
  prompt_message text;
begin
  select * into dev
  from public.require_developer(array['super_developer', 'support_developer', 'billing_support', 'security_admin']);

  select *
    into target
  from public.churches c
  where c.id::text = p_church_id or c."placeId"::text = p_church_id
  limit 1;

  if target.id is null then
    raise exception 'Church not found.';
  end if;

  select *
    into owner
  from public.users u
  where u.id::text = coalesce(target."ownerUserId", target.owner_user_id::text)
     or u.uid = coalesce(target."ownerUserId", target.owner_user_id::text)
  limit 1;

  recipient := coalesce(nullif(target.contact_email, ''), nullif(owner.email, ''));
  prompt_message := coalesce(
    nullif(trim(p_message), ''),
    'Please complete your Grace Connect church profile, including contact information, founding details, service information, address, and any missing setup items.'
  );

  if recipient is null then
    raise exception 'This church has no contact email or owner email to receive a setup prompt.';
  end if;

  perform public.queue_app_email(
    recipient,
    'Grace Connect church profile setup needed',
    '<p>Hello,</p><p>' || prompt_message || '</p><p>Open Grace Connect and go to Settings > Church Settings to complete the profile for <strong>' || coalesce(target.display_name, target.name, target.id::text) || '</strong>.</p>',
    prompt_message,
    'church_setup_prompt',
    target.id::text,
    owner.id,
    jsonb_build_object('churchId', coalesce(target."placeId", target.id::text), 'developer', dev.email)
  );

  perform public.log_developer_action(
    'church_setup_prompt_sent',
    'church',
    coalesce(target."placeId", target.id::text),
    jsonb_build_object('recipient', recipient)
  );

  return jsonb_build_object('ok', true, 'recipient', recipient);
end;
$$;

create or replace function public.developer_approve_church_registration(p_church_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  request_uuid uuid;
  request_row record;
  approved_church_id text;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  begin
    request_uuid := p_church_id::uuid;
  exception when others then
    request_uuid := null;
  end;

  if request_uuid is not null
     and exists (select 1 from public.church_registration_requests where id = request_uuid) then
    select * into request_row from public.church_registration_requests where id = request_uuid;
    approved_church_id := public.approve_church_registration(request_uuid, 'Approved from developer portal.');
    perform public.log_developer_action('church_registration_approved', 'church_registration_request', request_uuid::text, jsonb_build_object('churchId', approved_church_id));
    perform public.queue_app_email(
      request_row.pastor_email,
      'Your Grace Connect church registration was approved',
      '<p>Your registration for <strong>' || coalesce(request_row.church_name_submitted, 'your church') || '</strong> was approved.</p><p>You can now sign in to Grace Connect and complete your church profile.</p>',
      'Your Grace Connect church registration was approved.',
      'church_registration',
      request_uuid::text,
      request_row.requested_by_user_id,
      jsonb_build_object('churchId', approved_church_id, 'developer', dev.email)
    );
    return jsonb_build_object('ok', true, 'church_id', approved_church_id);
  end if;

  update public.churches
     set church_status = 'approved',
         status = 'active',
         public_visibility = true,
         approved_at = coalesce(approved_at, now()),
         approved_by = dev.user_id,
         updated_at = now()
   where id::text = p_church_id or "placeId"::text = p_church_id
   returning coalesce("placeId", id::text) into approved_church_id;

  if approved_church_id is null then
    raise exception 'Church registration request or church not found';
  end if;

  perform public.log_developer_action('church_approved', 'church', approved_church_id, '{}'::jsonb);
  return jsonb_build_object('ok', true, 'church_id', approved_church_id);
end;
$$;

create or replace function public.developer_reject_church_registration(
  p_church_id text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
  request_uuid uuid;
  request_row record;
begin
  select * into dev from public.require_developer(array['super_developer', 'support_developer', 'security_admin']);

  begin
    request_uuid := p_church_id::uuid;
  exception when others then
    request_uuid := null;
  end;

  if request_uuid is not null
     and exists (select 1 from public.church_registration_requests where id = request_uuid) then
    select * into request_row from public.church_registration_requests where id = request_uuid;
    perform public.reject_church_registration(request_uuid, p_reason);
    perform public.log_developer_action('church_registration_rejected', 'church_registration_request', request_uuid::text, jsonb_build_object('reason', p_reason));
    perform public.queue_app_email(
      request_row.pastor_email,
      'Your Grace Connect church registration needs attention',
      '<p>Your registration for <strong>' || coalesce(request_row.church_name_submitted, 'your church') || '</strong> was not approved yet.</p><p><strong>Reason:</strong> ' || coalesce(nullif(trim(p_reason), ''), 'Please contact Grace Connect support for details.') || '</p>',
      'Your Grace Connect church registration was not approved yet. Reason: ' || coalesce(nullif(trim(p_reason), ''), 'Please contact Grace Connect support for details.'),
      'church_registration',
      request_uuid::text,
      request_row.requested_by_user_id,
      jsonb_build_object('developer', dev.email)
    );
    return jsonb_build_object('ok', true);
  end if;

  raise exception 'Church registration request not found';
end;
$$;

create or replace function public.developer_get_dashboard()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  dev public.developer_accounts;
begin
  select * into dev from public.require_developer(null);

  return jsonb_build_object(
    'total_users', (select count(*) from public.users),
    'pending_members', (select count(*) from public.church_memberships where membership_status = 'pending'),
    'open_support_tickets', (select count(*) from public.support_tickets where status in ('open', 'acknowledged', 'in_review')),
    'total_churches', (select count(*) from public.churches),
    'approved_churches', (select count(*) from public.churches where church_status = 'approved' or status in ('active', 'verified')),
    'pending_churches', (select count(*) from public.church_registration_requests where application_status in ('submitted', 'under_review', 'needs_information')),
    'suspended_churches', (select count(*) from public.churches where church_status = 'suspended'),
    'subscribed_churches', (
      select count(*)
      from public.churches c
      where exists (
        select 1
        from public.church_subscriptions cs
        where cs.church_id in (c.id::text, c."placeId"::text)
          and cs.status in ('active', 'trialing', 'grace_period')
          and (
            greatest(
              coalesce(cs.current_period_end, '-infinity'::timestamptz),
              coalesce(cs.free_until, '-infinity'::timestamptz),
              coalesce(cs.grace_until, '-infinity'::timestamptz)
            ) = '-infinity'::timestamptz
            or greatest(
              coalesce(cs.current_period_end, '-infinity'::timestamptz),
              coalesce(cs.free_until, '-infinity'::timestamptz),
              coalesce(cs.grace_until, '-infinity'::timestamptz)
            ) >= now()
          )
      )
    ),
    'unsubscribed_churches', (
      select count(*)
      from public.churches c
      where (c.church_status = 'approved' or c.status in ('active', 'verified'))
        and not exists (
          select 1
          from public.church_subscriptions cs
          where cs.church_id in (c.id::text, c."placeId"::text)
            and cs.status in ('active', 'trialing', 'grace_period')
            and (
              greatest(
                coalesce(cs.current_period_end, '-infinity'::timestamptz),
                coalesce(cs.free_until, '-infinity'::timestamptz),
                coalesce(cs.grace_until, '-infinity'::timestamptz)
              ) = '-infinity'::timestamptz
              or greatest(
                coalesce(cs.current_period_end, '-infinity'::timestamptz),
                coalesce(cs.free_until, '-infinity'::timestamptz),
                coalesce(cs.grace_until, '-infinity'::timestamptz)
              ) >= now()
            )
        )
    ),
    'developer_accounts', (select count(*) from public.developer_accounts where status = 'active'),
    'recent_signups', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from (
        select id, email, "fullName", "placeName", "accountState" as "approvalStatus", "joinDate"
        from public.users
        order by "joinDate" desc nulls last
        limit 8
      ) r
    ),
    'churches_missing_setup', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from (
        select
          c.id,
          c."placeId",
          coalesce(c.display_name, c.name) as name,
          c.address,
          c."ownerUserId",
          c.contact_email,
          array_remove(array[
            case when coalesce(c."ownerUserId", '') = '' and c.owner_user_id is null then 'owner' end,
            case when nullif(c.address, '') is null then 'address' end,
            case when nullif(c.about, '') is null then 'about' end,
            case when c.founded_year is null then 'founded year' end,
            case when nullif(coalesce(c.contact_email, c.contact_phone), '') is null then 'contact' end
          ], null) as missing_items
        from public.churches c
        where (c.church_status = 'approved' or c.status in ('active', 'verified'))
          and (
            coalesce(c."ownerUserId", '') = ''
            or c.owner_user_id is null
            or nullif(c.address, '') is null
            or nullif(c.about, '') is null
            or c.founded_year is null
            or nullif(coalesce(c.contact_email, c.contact_phone), '') is null
          )
        order by c."createdAt" desc nulls last
        limit 8
      ) r
    )
  );
end;
$$;

revoke execute on function public.queue_app_email(text, text, text, text, text, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.submit_support_ticket(text, text, text, text, text, jsonb, text[]) to authenticated;
grant execute on function public.developer_list_support_tickets(text, text) to authenticated;
grant execute on function public.developer_update_support_ticket(text, text, text) to authenticated;
grant execute on function public.update_church_profile(text, text, text, text, text, text, integer, text, text, text, text) to authenticated;
grant execute on function public.developer_get_church_detail(text) to authenticated;
grant execute on function public.developer_list_church_registration_requests(text, text) to authenticated;
grant execute on function public.developer_send_church_setup_prompt(text, text) to authenticated;
grant execute on function public.get_public_church_directory(text) to anon, authenticated;
grant execute on function public.developer_approve_church_registration(text) to authenticated;
grant execute on function public.developer_reject_church_registration(text, text) to authenticated;
grant execute on function public.developer_get_dashboard() to authenticated;
