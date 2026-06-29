import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('one-day beta hardening guards', () {
    test('mobile attendance does not invoke the service finalizer', () {
      final source =
          File('lib/services/attendance_service.dart').readAsStringSync();

      expect(source, isNot(contains('finalize-service-attendance')));
      expect(source, contains("prefs.getBool('auto_check_in') ?? false"));
    });

    test('attendance finalizer is cron-secret only', () {
      final source =
          File('supabase/functions/finalize-service-attendance/index.ts')
              .readAsStringSync();

      expect(source,
          contains('requireCronSecret(request, "ATTENDANCE_CRON_SECRET")'));
      expect(source, isNot(contains('authenticatedUser(request)')));
      expect(source, contains('.from("church_memberships")'));
    });

    test('round 8 migration restores canonical church registration contract',
        () {
      final source = File(
        'supabase/migrations/20260629120000_p0_one_day_beta_hardening.sql',
      ).readAsStringSync();

      expect(
          source,
          contains(
              'drop function if exists public.submit_church_registration'));
      expect(source, contains('returns uuid'));
      expect(source, contains('church_name_submitted'));
      expect(source, contains('custom_denomination_name'));
      expect(source, contains('pastor_email'));
      expect(
          source,
          contains(
              'drop function if exists public.developer_list_churches(text)'));
      expect(source, contains('attendance_cron_secret'));
    });

    test('mobile signup gates account creation behind policy acceptance', () {
      final source = File('lib/screens/signup screen/signup_screen.dart')
          .readAsStringSync();

      expect(source, contains("getRequiredPolicies('member_signup')"));
      expect(source, contains('CheckboxListTile'));
      expect(source, contains('acceptedPolicySnapshot'));
      expect(source, contains("source: 'flutter_signup'"));
      expect(source, contains('canLaunchUrl'));
    });

    test('daily quiz shows final answer feedback before results', () {
      final source =
          File('lib/screens/bible/bible_quiz_screen.dart').readAsStringSync();

      expect(source, contains('_pendingCompletion'));
      expect(source, contains('See Results'));
      expect(source, contains('Correct answer:'));
    });

    test('community feed and statuses use community media video storage', () {
      final feedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final serviceSource =
          File('lib/services/community_service.dart').readAsStringSync();
      final migrationSource = File(
        'supabase/migrations/20260629133000_enable_community_video_media.sql',
      ).readAsStringSync();

      expect(feedSource, contains('pickStoryVideo'));
      expect(feedSource, contains('Video attached'));
      expect(serviceSource, contains("_bucketName = 'community_media'"));
      expect(migrationSource, contains("'community_media'"));
      expect(migrationSource, contains("'video/mp4'"));
      expect(migrationSource, contains("'video/webm'"));
    });

    test('church subscription state is church-level and developer managed', () {
      final migrationSource = File(
        'supabase/migrations/20260629143000_church_subscription_platform_sync.sql',
      ).readAsStringSync();
      final gateSource =
          File('lib/screens/membership/membership_gate_screen.dart')
              .readAsStringSync();
      final tabSource =
          File('lib/screens/main/main_tabs_screen.dart').readAsStringSync();
      final developerServiceSource =
          File('lib/services/developer_service.dart').readAsStringSync();

      expect(migrationSource, contains('public.church_subscriptions'));
      expect(migrationSource, contains('get_church_subscription_context'));
      expect(migrationSource, contains('developer_set_church_subscription'));
      expect(migrationSource, contains('developer_clear_church_subscription'));
      expect(migrationSource, contains('subscription_active'));
      expect(gateSource, contains('Subscription Required'));
      expect(gateSource, contains("route == '/community'"));
      expect(tabSource, contains('_subscriptionLimited'));
      expect(tabSource, contains('NeverScrollableScrollPhysics'));
      expect(developerServiceSource, contains('developer_get_dashboard'));
      expect(developerServiceSource, contains('developer_list_churches'));
      expect(developerServiceSource, isNot(contains('church_locations')));
    });

    test('developer portal support issues and church drill-down are wired', () {
      final migrationSource = File(
        'supabase/migrations/20260629153000_developer_portal_issues_church_profiles.sql',
      ).readAsStringSync();
      final supportSource =
          File('lib/screens/profile/support_screen.dart').readAsStringSync();
      final feedbackSource =
          File('lib/screens/settings/feedback_screen.dart').readAsStringSync();
      final churchSettingsSource =
          File('lib/screens/settings/church_admin_settings_screen.dart')
              .readAsStringSync();
      final portalSource =
          File('../Grace_Connect_Landing/js/developer-portal.js')
              .readAsStringSync();
      final portalHtml = File('../Grace_Connect_Landing/developer/index.html')
          .readAsStringSync();
      final legacyChurchSource = File(
        'supabase/migrations/20260629155000_publish_legacy_active_churches.sql',
      ).readAsStringSync();

      expect(migrationSource, contains('public.support_tickets'));
      expect(migrationSource, contains('public.email_notification_queue'));
      expect(migrationSource, contains('submit_support_ticket'));
      expect(migrationSource, contains('developer_list_support_tickets'));
      expect(migrationSource, contains('developer_update_support_ticket'));
      expect(migrationSource, contains('developer_get_church_detail'));
      expect(migrationSource,
          contains('developer_list_church_registration_requests'));
      expect(migrationSource, contains('developer_send_church_setup_prompt'));
      expect(migrationSource, contains('update_church_profile'));
      expect(migrationSource, contains("status in ('active', 'verified')"));
      expect(legacyChurchSource, contains('public_visibility = true'));
      expect(legacyChurchSource, contains('get_public_church_directory'));
      expect(legacyChurchSource, contains('c."placeId"'));

      expect(supportSource, contains('submit_support_ticket'));
      expect(supportSource,
          isNot(contains('EmailService().sendSupportReportEmail')));
      expect(feedbackSource, contains('submit_support_ticket'));
      expect(churchSettingsSource, contains('_aboutController'));
      expect(churchSettingsSource, contains('_serviceTimesController'));

      expect(portalHtml, contains('data-view="requests"'));
      expect(portalHtml, contains('data-view="issues"'));
      expect(portalHtml, isNot(contains('data-view="members"')));
      expect(portalSource, contains('developer_list_support_tickets'));
      expect(portalSource, contains('developer_get_church_detail'));
      expect(portalSource,
          contains('developer_list_church_registration_requests'));
      expect(portalSource, isNot(contains('approve-member')));
      expect(portalSource, isNot(contains('developer_approve_member_request')));
    });
  });
}
