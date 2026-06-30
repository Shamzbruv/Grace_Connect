-- One-time beta reset requested before retesting onboarding from scratch.
-- Keep platform/legal seed data and developer accounts, but remove church data
-- and user church assignments so the app starts with no registered churches.

do $$
declare
  table_names text[] := array[
    'quiz_attempt_answers',
    'quiz_attempts',
    'monthly_quiz_winners',
    'quiz_security_events',
    'daily_bible_quiz_questions',
    'daily_bible_quizzes',
    'quiz_generation_runs',
    'community_comments',
    'community_posts',
    'community_stories',
    'content_reports',
    'user_blocks',
    'group_messages',
    'direct_message_grants',
    'direct_messages',
    'direct_conversations',
    'notifications',
    'system_notification_outbox',
    'email_notification_queue',
    'support_tickets',
    'priority_follow_ups',
    'attendance_finalized_services',
    'church_attendance_alert_settings',
    'church_locations',
    'church_transfer_requests',
    'church_member_roles',
    'church_memberships',
    'church_subscriptions',
    'ministry_managers',
    'ministries',
    'announcements',
    'events',
    'attendance_records',
    'attendance_sessions',
    'attendance_checkins',
    'donations',
    'prayers',
    'prayer_requests',
    'counseling_requests',
    'care_cases',
    'testimonies',
    'study_groups',
    'bible_nudges',
    'bible_streaks',
    'daily_motivations',
    'live_streams',
    'service_schedules',
    'schedule_assignments',
    'church_approval_audit_events',
    'church_registration_requests',
    'developer_audit_logs',
    'churches'
  ];
  table_name text;
begin
  foreach table_name in array table_names loop
    if to_regclass(format('public.%I', table_name)) is not null then
      execute format('delete from public.%I', table_name);
    end if;
  end loop;

  if to_regclass('public.users') is not null then
    update public.users
    set "placeId" = null,
        "placeName" = null,
        "accountState" = 'active',
        roles = case
          when coalesce("isDeveloper", false) then roles
          else array['Member']::text[]
        end;
  end if;
end;
$$;
