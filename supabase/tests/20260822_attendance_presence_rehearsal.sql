\set ON_ERROR_STOP on

begin;
\ir ../migrations/20260822025758_attendance_presence_state_race_guard.sql

select plan(14);

select ok(
  to_regclass('public.attendance_presence_claims') is not null,
  'server-owned presence claims can be created on the production schema'
);

select is(
  (
    select c.is_nullable
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'attendance'
      and c.column_name = 'service_date'
  ),
  'NO',
  'attendance has a required logical service date'
);

select ok(
  not has_table_privilege('authenticated', 'public.attendance', 'INSERT'),
  'authenticated clients cannot bypass the attendance RPC'
);

select ok(
  not has_table_privilege('authenticated', 'public.attendance', 'UPDATE'),
  'authenticated clients cannot overwrite finalized attendance directly'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.record_my_attendance(text,text,timestamptz,text,boolean,text,integer,text,text,text)',
    'EXECUTE'
  ),
  'authenticated clients can use the validated attendance writer'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.record_my_attendance_presence(text,text,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients can persist a bounded countdown claim'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.finalize_attendance_service_v2(text,text,date,text)',
    'EXECUTE'
  ),
  'the attendance worker can execute the atomic closeout RPC'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.insert_absent_attendance_rows(jsonb)',
    'EXECUTE'
  ),
  'the split legacy absence writer is retired'
);

select ok(
  exists (
    select 1
    from pg_indexes idx
    where idx.schemaname = 'public'
      and idx.indexname =
        'attendance_one_record_per_member_service_occurrence_idx'
      and idx.indexdef like '%church_id, user_id, service_id, service_date%'
  ),
  'attendance is unique by logical recurring-service occurrence'
);

select ok(
  exists (
    select 1
    from pg_trigger trg
    join pg_class rel on rel.oid = trg.tgrelid
    where rel.oid = 'public.attendance'::regclass
      and trg.tgname = 'attendance_confirm_presence_claim'
      and not trg.tgisinternal
  ),
  'a committed present row confirms its pending presence claim'
);

select ok(
  exists (
    select 1
    from pg_trigger trg
    join pg_class rel on rel.oid = trg.tgrelid
    where rel.oid = 'public.attendance'::regclass
      and trg.tgname = 'attendance_guard_confirmed_presence'
      and not trg.tgisinternal
  ),
  'confirmed presence cannot be downgraded to automatic absence'
);

select ok(
  position(
    'church_memberships' in pg_get_functiondef(
      'public.finalize_attendance_service_v2(text,text,date,text)'::regprocedure
    )
  ) > 0,
  'atomic closeout derives its population from reviewed memberships'
);

select ok(
  position(
    'public.users' in pg_get_functiondef(
      'public.finalize_attendance_service_v2(text,text,date,text)'::regprocedure
    )
  ) = 0,
  'atomic closeout does not fall back to stale profile church fields'
);

select ok(
  not exists (
    select 1
    from pg_proc proc
    join pg_namespace ns on ns.oid = proc.pronamespace
    where ns.nspname in ('public', 'private')
      and proc.prosecdef
      and proc.proname in (
        'is_active_attendance_member',
        'attendance_service_bounds',
        'attendance_service_occurrence',
        'record_my_attendance_presence',
        'cancel_my_attendance_presence',
        'record_my_attendance',
        'confirm_attendance_presence_claim',
        'finalize_attendance_service_v2',
        'refresh_attendance_priority_list'
      )
      and (
        proc.proconfig is null
        or not exists (
          select 1
          from unnest(proc.proconfig) setting
          where setting = 'search_path=""'
             or setting = 'search_path='
        )
      )
  ),
  'attendance SECURITY DEFINER functions pin an empty search path'
);

select * from finish();
rollback;
