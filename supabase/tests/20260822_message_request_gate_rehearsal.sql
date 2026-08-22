\set ON_ERROR_STOP on

-- This test applies the production migration against the linked schema inside
-- one transaction and always rolls it back. It catches dependencies, DDL/SQL
-- syntax, policy, signature, and privilege drift without deploying anything.
begin;
\ir ../migrations/20260822025626_cross_church_message_request_gate.sql

select plan(13);

select ok(
  to_regclass('public.direct_message_requests') is not null,
  'message-request table can be created on the production schema'
);

select ok(
  to_regclass('public.direct_message_request_push_deliveries') is not null,
  'durable push-delivery queue can be created on the production schema'
);

select ok(
  to_regclass('public.bible_nudge_push_deliveries') is not null,
  'durable Bible-Nudge push queue can be created on the production schema'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.bible_nudge_push_deliveries',
    'SELECT'
  ),
  'authenticated users cannot inspect the internal Bible-Nudge delivery queue'
);

select is(
  (
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'direct_message_requests'
  ),
  true,
  'message requests have RLS enabled'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.direct_message_requests',
    'INSERT'
  ),
  'authenticated users cannot bypass the request RPC with table inserts'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.request_direct_message(text,text,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users can invoke the guarded request RPC'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_notification(uuid,uuid,text,text,text,text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated users cannot forge arbitrary in-app notifications'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_due_message_request_push_deliveries(integer)',
    'EXECUTE'
  ),
  'only the service retry worker receives delivery-claim access'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.claim_due_bible_nudge_push_deliveries(integer)',
    'EXECUTE'
  ),
  'the service retry worker can claim Bible-Nudge delivery leases'
);

select ok(
  exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'direct_messages'
      and p.policyname = 'Members send own direct messages'
      and p.with_check like '%can_send_direct_message_to_conversation%'
  ),
  'direct message inserts are protected by the server consent gate'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname in (
        'resolve_direct_message_user_id',
        'direct_message_identity_keys',
        'direct_message_viewer_identity_keys',
        'direct_message_active_church_keys',
        'users_share_active_church',
        'users_have_different_active_churches',
        'can_send_bible_nudge',
        'has_direct_message_grant',
        'direct_message_pair_is_blocked',
        'can_direct_message_pair',
        'can_send_direct_message_to_conversation',
        'create_notification',
        'request_direct_message',
        'respond_to_direct_message_request',
        'cancel_direct_message_request',
        'claim_message_request_push_delivery',
        'claim_due_message_request_push_deliveries',
        'complete_message_request_push_delivery',
        'get_or_create_direct_conversation',
        'notify_on_direct_message',
        'accept_bible_nudge_and_grant_messages',
        'notify_bible_nudge_lifecycle'
      )
      and (
        p.proconfig is null
        or not exists (
          select 1
          from unnest(p.proconfig) as setting
          where setting like 'search_path=%'
            and setting not like '%public%'
        )
      )
  ),
  'all request-gate SECURITY DEFINER functions pin an empty search path'
);

select ok(
  exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where c.oid = 'public.bible_nudges'::regclass
      and t.tgname = 'notify_bible_nudge_response_trigger'
      and not t.tgisinternal
  ),
  'Bible-Nudge decisions create transactional in-app notifications'
);

select * from finish();
rollback;
