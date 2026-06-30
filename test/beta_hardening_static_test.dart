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

    test('pending and churchless users get browse-only feed access', () {
      final gateSource =
          File('lib/screens/membership/membership_gate_screen.dart')
              .readAsStringSync();
      final tabSource =
          File('lib/screens/main/main_tabs_screen.dart').readAsStringSync();
      final feedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final interactionLock = File(
        'supabase/migrations/20260630090000_browse_only_feed_interaction_lock.sql',
      ).readAsStringSync();
      final resetSource = File(
        'supabase/migrations/20260630093000_reset_beta_platform_to_empty_churches.sql',
      ).readAsStringSync();

      expect(gateSource, contains('hasPendingChurchApplication'));
      expect(gateSource, contains('hasPendingMembership'));
      expect(gateSource, contains('membershipLimited: true'));
      expect(gateSource, contains("route == '/community'"));
      expect(gateSource, contains('Browse Feed For Now'));
      expect(tabSource, contains('_feedOnlyLimited'));
      expect(feedSource,
          contains('Showing public posts shared across Grace Connect'));
      expect(feedSource, contains('readOnly: _isBrowseOnly(churchId)'));
      expect(feedSource, contains('if (!browseOnly) const InboxIconButton()'));
      expect(
          interactionLock,
          contains(
              'Church approval is required before interacting with the feed.'));
      expect(resetSource, contains("'church_registration_requests'"));
      expect(resetSource, contains("'churches'"));
      expect(resetSource, contains('"placeId" = null'));
      expect(resetSource, contains('coalesce("isDeveloper", false)'));
    });

    test('developer portal support issues and church drill-down are wired', () {
      final migrationSource = File(
        'supabase/migrations/20260629153000_developer_portal_issues_church_profiles.sql',
      ).readAsStringSync();
      final supportSource =
          File('lib/screens/profile/support_screen.dart').readAsStringSync();
      final feedbackSource =
          File('lib/screens/settings/feedback_screen.dart').readAsStringSync();
      final emailDeliverySource =
          File('lib/services/email_delivery_service.dart').readAsStringSync();
      final mailerSource =
          File('supabase/functions/grace-mailer/index.ts').readAsStringSync();
      final supabaseConfig = File('supabase/config.toml').readAsStringSync();
      final churchSettingsSource =
          File('lib/screens/settings/church_admin_settings_screen.dart')
              .readAsStringSync();
      final portalFile =
          File('../Grace_Connect_Landing/js/developer-portal.js');
      final publicMainFile = File('../Grace_Connect_Landing/js/main.js');
      final portalHtmlFile =
          File('../Grace_Connect_Landing/developer/index.html');
      final publicHomeFile = File('../Grace_Connect_Landing/index.html');
      final legacyChurchSource = File(
        'supabase/migrations/20260629155000_publish_legacy_active_churches.sql',
      ).readAsStringSync();
      final userManagementSource = File(
        'supabase/migrations/20260630103000_developer_user_management.sql',
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
      expect(supportSource, contains('EmailDeliveryService'));
      expect(feedbackSource, contains('submit_support_ticket'));
      expect(feedbackSource, contains('EmailDeliveryService'));
      expect(emailDeliverySource, contains('grace-mailer'));
      expect(emailDeliverySource, contains('flush-support-ticket'));
      expect(mailerSource, contains('RESEND_API_KEY'));
      expect(mailerSource, contains('auth-signup'));
      expect(mailerSource, contains('flush-queue'));
      expect(mailerSource, contains('flush-support-ticket'));
      expect(mailerSource, contains('email_notification_queue'));
      expect(supabaseConfig, contains('[functions.grace-mailer]'));
      expect(churchSettingsSource, contains('_aboutController'));
      expect(churchSettingsSource, contains('_serviceTimesController'));

      if (portalFile.existsSync() &&
          publicMainFile.existsSync() &&
          portalHtmlFile.existsSync() &&
          publicHomeFile.existsSync()) {
        final portalSource = portalFile.readAsStringSync();
        final publicMainSource = publicMainFile.readAsStringSync();
        final portalHtml = portalHtmlFile.readAsStringSync();
        final publicHomeHtml = publicHomeFile.readAsStringSync();

        expect(portalHtml, contains('data-view="requests"'));
        expect(portalHtml, contains('data-view="issues"'));
        expect(portalHtml, contains('../assets/favicon.png'));
        expect(publicHomeHtml, contains('assets/favicon.png'));
        expect(portalHtml, isNot(contains('data-view="members"')));
        expect(portalSource, contains('developer_list_support_tickets'));
        expect(portalSource, contains('developer_get_church_detail'));
        expect(portalSource,
            contains('developer_list_church_registration_requests'));
        expect(portalSource, contains('approve-member'));
        expect(portalSource, contains('developer_approve_member_request'));
        expect(portalSource, contains('developer_update_user_access'));
        expect(portalSource, contains('developer_delete_user_account'));
        expect(portalSource, contains('flushQueuedEmails'));
        expect(portalSource, contains('grace-mailer'));
        expect(publicMainSource, contains('auth-signup'));
        expect(publicMainSource, contains('web_church_registration'));
        expect(publicMainSource, contains('web_member_signup'));
      }

      expect(userManagementSource, contains('developer_update_user_access'));
      expect(userManagementSource, contains('developer_delete_user_account'));
      expect(
          userManagementSource, contains('developer_approve_member_request'));
      expect(userManagementSource, contains('"appPrivileges"'));
    });

    test('android release identity and permissions are beta-safe', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final googleServices =
          File('android/app/google-services.json').readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/love/graceconnect/MainActivity.kt',
      ).readAsStringSync();

      expect(gradle, contains('"love.graceconnect"'));
      expect(gradle, contains('versionCode 14'));
      expect(gradle, contains('versionName "1.0.13-beta"'));
      expect(activity, contains('package love.graceconnect'));
      expect(manifest, contains('love.graceconnect.MainActivity'));
      expect(googleServices, contains('"package_name": "love.graceconnect"'));
      expect(googleServices, isNot(contains('com.example.grace_connect')));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
      expect(manifest, isNot(contains('FOREGROUND_SERVICE_LOCATION')));
    });

    test('registration RPC and beta network crashes are hardened', () {
      final registrationRpc = File(
        'supabase/migrations/20260630112500_fix_church_registration_conflict_rpc_ordering.sql',
      ).readAsStringSync();
      final resilienceSource =
          File('lib/services/supabase_resilience.dart').readAsStringSync();
      final mainSource = File('lib/main.dart').readAsStringSync();
      final quizSource =
          File('lib/services/daily_bible_quiz_service.dart').readAsStringSync();
      final motivationSource =
          File('lib/services/daily_motivation_service.dart').readAsStringSync();

      expect(registrationRpc, contains('p_parish text := parish'));
      expect(registrationRpc, contains('candidate.parish'));
      expect(registrationRpc, contains('ranked as'));
      expect(registrationRpc, contains('grant execute on function'));
      expect(resilienceSource, contains('isTransientNetworkError'));
      expect(
          resilienceSource, contains('connection closed while receiving data'));
      expect(resilienceSource, contains('software caused connection abort'));
      expect(mainSource, contains('recordFlutterError('));
      expect(mainSource, contains('fatal: false'));
      expect(quizSource, contains('_invokeQuietly'));
      expect(quizSource, contains('timeout(const Duration(seconds: 18))'));
      expect(motivationSource, contains('generate-daily-motivation'));
      expect(
          motivationSource, contains('timeout(const Duration(seconds: 18))'));
    });

    test('push notifications are opt-in and topic broadcasts stay public', () {
      final serviceSource =
          File('lib/services/notification_service.dart').readAsStringSync();
      final settingsSource =
          File('lib/screens/settings/notification_settings_screen.dart')
              .readAsStringSync();
      final functionsSource = File('functions/index.js').readAsStringSync();

      expect(serviceSource,
          isNot(contains('await _messaging.requestPermission();')));
      expect(serviceSource, contains('Future<bool> ensurePushPermission()'));
      expect(
          serviceSource, contains("churchWidePrefKey = 'notify_church_wide'"));
      expect(serviceSource, contains("prefs.getBool(prefKey) ?? false"));
      expect(serviceSource, contains('publicBroadcastTypes'));
      expect(settingsSource, contains('_churchAnnouncements = false'));
      expect(settingsSource, contains('ensurePushPermission'));
      expect(functionsSource, contains('PUBLIC_BROADCAST_TYPES'));
      expect(functionsSource,
          contains('Only public church-wide broadcasts can use topic push.'));
    });

    test('legacy express backend cannot start accidentally', () {
      final legacySource =
          File('graceconnect_backend/server.js').readAsStringSync();
      final legacyReadme =
          File('graceconnect_backend/README.md').readAsStringSync();

      expect(
        legacySource,
        contains("GRACECONNECT_ENABLE_LEGACY_BACKEND !== 'true'"),
      );
      expect(legacyReadme, contains('Legacy Backend Archive'));
      expect(
        legacyReadme,
        contains('not part of the active Grace Connect production'),
      );
    });
  });
}
