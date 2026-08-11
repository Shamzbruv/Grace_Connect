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
      final accessSource =
          File('lib/access/app_access_context.dart').readAsStringSync();
      final unavailableSource =
          File('lib/screens/access/feature_unavailable_screen.dart')
              .readAsStringSync();
      final mainSource = File('lib/main.dart').readAsStringSync();
      final developerServiceSource =
          File('lib/services/developer_service.dart').readAsStringSync();

      expect(migrationSource, contains('public.church_subscriptions'));
      expect(migrationSource, contains('get_church_subscription_context'));
      expect(migrationSource, contains('developer_set_church_subscription'));
      expect(migrationSource, contains('developer_clear_church_subscription'));
      expect(migrationSource, contains('subscription_active'));
      expect(gateSource, contains('FeatureAccessGuard'));
      expect(unavailableSource, contains('unavailableMessageFor'));
      expect(unavailableSource, contains('Find a Church'));
      expect(mainSource, contains("'/bible': (context) => _protected("));
      expect(mainSource, contains('feature: AppFeature.bibleReading'));
      expect(accessSource, contains('case AppFeature.bibleReading:'));
      expect(accessSource, contains('case AppFeature.dailyWord:'));
      expect(tabSource, contains('access.hasActiveChurchSubscription'));
      expect(tabSource, contains('UnconnectedDashboard(access: access)'));
      expect(tabSource, contains('allowDailyQuiz: true'));
      expect(developerServiceSource, contains('developer_get_dashboard'));
      expect(developerServiceSource, contains('developer_list_churches'));
      expect(developerServiceSource, isNot(contains('church_locations')));
    });

    test('feature access keeps public tools open and church tools protected',
        () {
      final gateSource =
          File('lib/screens/membership/membership_gate_screen.dart')
              .readAsStringSync();
      final tabSource =
          File('lib/screens/main/main_tabs_screen.dart').readAsStringSync();
      final accessSource =
          File('lib/access/app_access_context.dart').readAsStringSync();
      final unconnectedDashboardSource = File(
        'lib/screens/dashboard/variants/unconnected_dashboard.dart',
      ).readAsStringSync();
      final interactionLock = File(
        'supabase/migrations/20260630090000_browse_only_feed_interaction_lock.sql',
      ).readAsStringSync();
      final resetSource = File(
        'supabase/migrations/20260630093000_reset_beta_platform_to_empty_churches.sql',
      ).readAsStringSync();

      expect(gateSource, contains('AppAccessContext('));
      expect(gateSource, contains('AppAccessScope('));
      expect(gateSource, contains('FeatureAccessGuard('));
      expect(accessSource, contains('case AppFeature.communityRead:'));
      expect(accessSource, contains('case AppFeature.bibleReading:'));
      expect(accessSource, contains('case AppFeature.memberDirectory:'));
      expect(accessSource, contains('return hasActiveChurchSubscription;'));
      expect(tabSource, contains('_primaryFeatures'));
      expect(tabSource, contains('access.hasActiveChurchSubscription'));
      expect(tabSource, contains('UnconnectedDashboard(access: access)'));
      expect(unconnectedDashboardSource, contains('hasPendingMembership'));
      expect(
          unconnectedDashboardSource, contains('hasPendingChurchApplication'));
      expect(unconnectedDashboardSource, contains("'Community', '/community'"));
      expect(unconnectedDashboardSource, contains("'Bible', '/bible'"));
      expect(unconnectedDashboardSource, contains('Church membership unlocks'));
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
      expect(feedbackSource, contains('support_attachments'));
      expect(feedbackSource, contains('_uploadAttachments'));
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

    test(
        'member review cards show requester details and same-church nudge is hidden',
        () {
      final membershipReviewSource =
          File('lib/screens/admin/membership_requests_screen.dart')
              .readAsStringSync();
      final membershipReviewMigration = File(
        'supabase/migrations/20260701031000_membership_review_details.sql',
      ).readAsStringSync();
      final memberListSource =
          File('lib/screens/members/members_list_screen.dart')
              .readAsStringSync();
      final communityFeedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final bibleNudgeServiceSource =
          File('lib/services/bible_nudge_service.dart').readAsStringSync();

      expect(
          membershipReviewSource, contains('list_church_membership_requests'));
      expect(membershipReviewSource, contains('request_message'));
      expect(membershipReviewSource, contains('No email on profile'));
      expect(membershipReviewSource, contains('No phone on profile'));
      expect(membershipReviewSource, contains('Message to leaders'));
      expect(membershipReviewMigration, contains('jsonb_build_object'));
      expect(membershipReviewMigration, contains('left join auth.users'));
      expect(membershipReviewMigration, contains('request_message'));
      expect(memberListSource,
          contains('!isOwnProfile && !isPrivate && !isSameChurch'));
      expect(communityFeedSource, contains('canNudgePerson'));
      expect(communityFeedSource, contains('_isDifferentKnownChurch'));
      expect(bibleNudgeServiceSource,
          contains('Bible Nudge is only for people outside your church'));
    });

    test('member approval honors explicit approveMembers privilege', () {
      final privilegeGateMigration = File(
        'supabase/migrations/20260702170000_member_approval_privilege_gate.sql',
      ).readAsStringSync();
      final membershipReviewSource =
          File('lib/screens/admin/membership_requests_screen.dart')
              .readAsStringSync();

      expect(
          privilegeGateMigration, contains('public.can_manage_church_members'));
      expect(privilegeGateMigration, contains('"appPrivileges"'));
      expect(privilegeGateMigration, contains("'approveMembers'"));
      expect(privilegeGateMigration, contains("'manageChurchSettings'"));
      expect(privilegeGateMigration, contains('cm.membership_status ='));
      expect(privilegeGateMigration, contains("c.church_status = 'approved'"));
      expect(membershipReviewSource,
          contains("approve ? 'approve_church_membership'"));
      expect(membershipReviewSource,
          contains("params: {'p_church_id': churchId}"));
    });

    test('android release identity and permissions are beta-safe', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final googleServices =
          File('android/app/google-services.json').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/love/graceconnect/MainActivity.kt',
      ).readAsStringSync();

      expect(gradle, contains('"love.graceconnect"'));
      expect(gradle, contains('versionCode 29'));
      expect(gradle, contains('versionName "1.0.27-beta"'));
      expect(pubspec, contains('version: "1.0.27-beta+29"'));
      expect(activity, contains('package love.graceconnect'));
      expect(manifest, contains('love.graceconnect.MainActivity'));
      expect(manifest, contains('default_notification_icon'));
      expect(manifest, contains('default_notification_channel_id'));
      expect(manifest, contains('grace_default_channel_v1'));
      expect(manifest, contains('@drawable/ic_stat_grace_connect'));
      expect(googleServices, contains('"package_name": "love.graceconnect"'));
      expect(googleServices, isNot(contains('com.example.grace_connect')));
      // Auto-attendance starts a visible foreground location service while the
      // member is using the app. It intentionally does not request unrestricted
      // Android background-location access.
      expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
      expect(
        manifest,
        contains('android.permission.FOREGROUND_SERVICE_LOCATION'),
      );
      expect(manifest, contains('android.permission.WAKE_LOCK'));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
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

    test(
        'push notifications prompt at startup and topic broadcasts stay scoped',
        () {
      final serviceSource =
          File('lib/services/notification_service.dart').readAsStringSync();
      final settingsSource =
          File('lib/screens/settings/notification_settings_screen.dart')
              .readAsStringSync();
      final functionsSource = File('functions/index.js').readAsStringSync();
      final membershipPushSource = File(
        'supabase/functions/send-membership-request-push/index.ts',
      ).readAsStringSync();
      final notificationMigration = File(
        'supabase/migrations/20260630205500_fix_member_approval_notifications.sql',
      ).readAsStringSync();

      expect(
          serviceSource, contains('ensureStartupPermissionsAndSubscriptions'));
      expect(serviceSource, contains('Future<bool> ensurePushPermission()'));
      expect(serviceSource, contains('requestNotificationsPermission'));
      expect(serviceSource, contains('Duration(hours: 3)'));
      expect(serviceSource, contains("church_\${churchId}_leaders"));
      expect(serviceSource, contains('send-membership-request-push'));
      expect(
          serviceSource, contains("churchWidePrefKey = 'notify_church_wide'"));
      expect(serviceSource, contains("prefs.getBool(prefKey) ?? false"));
      expect(serviceSource, contains('publicBroadcastTypes'));
      expect(settingsSource, contains('_churchAnnouncements = false'));
      expect(settingsSource, contains('ensurePushPermission'));
      expect(functionsSource, contains('PUBLIC_BROADCAST_TYPES'));
      expect(functionsSource,
          contains('Only public church-wide broadcasts can use topic push.'));
      expect(membershipPushSource, contains('authenticatedUser'));
      expect(membershipPushSource, contains('church_\${churchId}_leaders'));
      expect(membershipPushSource, contains('/membership_requests'));
      expect(
          notificationMigration, contains('developer_approve_member_request'));
      expect(notificationMigration,
          isNot(contains('left join public.users u on u.id = cm.user_id')));
      expect(notificationMigration, contains('/membership_requests'));
    });

    test('Google Play reviewer demo access stays non-developer', () {
      final migrationSource = File(
        'supabase/migrations/20260630193000_play_review_demo_access.sql',
      ).readAsStringSync();
      final scriptSource = File('scripts/setup_google_play_review_accounts.py')
          .readAsStringSync();
      final docsSource =
          File('docs/google_play_review_access.md').readAsStringSync();
      final settingsSource =
          File('lib/screens/settings/settings_home_screen.dart')
              .readAsStringSync();
      final appSettingsSource =
          File('lib/screens/settings/app_settings_screen.dart')
              .readAsStringSync();

      expect(migrationSource, contains('Grace Connect Review Demo Church'));
      expect(migrationSource, contains('play_review_demo'));
      expect(migrationSource, contains('public_visibility'));
      expect(migrationSource, contains('false'));
      expect(migrationSource, contains('"isDeveloper"'));
      expect(scriptSource, contains('PLAY_REVIEW_MEMBER_EMAIL'));
      expect(scriptSource, contains('PLAY_REVIEW_ADMIN_PASSWORD'));
      expect(scriptSource, contains('"isDeveloper": False'));
      expect(scriptSource, isNot(contains('developer_accounts')));
      expect(
          docsSource,
          contains(
              'Developer Portal / Developer Console access is intentionally not provided'));
      expect(settingsSource, contains('hasDeveloperAccess'));
      expect(appSettingsSource, contains('terms.html'));
      expect(appSettingsSource, contains('privacy.html'));
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

    test('Android release builds validate Maps and package config', () {
      final gradleSource = File('android/app/build.gradle').readAsStringSync();
      final manifestSource =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final releaseDocs =
          File('docs/play_internal_testing_release.md').readAsStringSync();

      expect(gradleSource, contains('validateGraceReleaseConfig'));
      expect(gradleSource, contains('findConfigValue'));
      expect(gradleSource, contains('def keyName = name.toString()'));
      expect(gradleSource, contains('project.hasProperty(keyName)'));
      expect(gradleSource, contains('localProperties.containsKey(keyName)'));
      expect(gradleSource, contains('GRACE_CONNECT_APPLICATION_ID'));
      expect(gradleSource, contains('GOOGLE_MAPS_API_KEY_ANDROID'));
      expect(gradleSource, contains('googleMapsApiKey'));
      expect(manifestSource, contains('com.google.android.geo.API_KEY'));
      expect(releaseDocs, contains('Maps SDK for Android'));
      expect(releaseDocs, contains('Places API (New)'));
      expect(releaseDocs, contains('Geocoding API'));
    });

    test('notifications and direct messages have P0 beta guards', () {
      final mainSource = File('lib/main.dart').readAsStringSync();
      final notificationSource =
          File('lib/services/notification_service.dart').readAsStringSync();
      final roleProviderSource =
          File('lib/providers/user_role_provider.dart').readAsStringSync();
      final messageSource =
          File('lib/services/direct_message_service.dart').readAsStringSync();

      expect(mainSource, contains('FirebaseMessaging.onBackgroundMessage'));
      expect(notificationSource, contains('showDataOnlyBackgroundMessage'));
      expect(notificationSource, contains("message.data['title']"));
      expect(
        notificationSource,
        contains('SupabaseClient get _supabase => Supabase.instance.client;'),
      );
      expect(
        roleProviderSource,
        contains('AttendanceService().stopMonitoring();'),
      );
      expect(messageSource, contains('sanitizeReplyContext'));
      expect(messageSource, contains('<String, dynamic>{}'));
    });

    test('app-wide live alerts and live viewer counts are wired', () {
      final notificationSource =
          File('lib/services/notification_service.dart').readAsStringSync();
      final functionsSource = File('functions/index.js').readAsStringSync();
      final adminLiveSource =
          File('lib/screens/admin/admin_stream_settings_screen.dart')
              .readAsStringSync();
      final liveSource =
          File('lib/screens/live_streaming/live_streaming_screen.dart')
              .readAsStringSync();
      final churchServiceSource =
          File('lib/services/church_service.dart').readAsStringSync();
      final migrationSource = File(
        'supabase/migrations/20260704120000_live_stream_presence.sql',
      ).readAsStringSync();

      expect(notificationSource, contains("appWideTopic = 'graceconnect_all'"));
      expect(notificationSource, contains('setAutoInitEnabled(true)'));
      expect(notificationSource, contains('userTopicFor'));
      expect(notificationSource, contains('sendDirectMessagePush'));
      expect(functionsSource, contains('APP_WIDE_TOPIC'));
      expect(functionsSource, contains('canSendDirectMessagePush'));
      expect(functionsSource, contains('"direct_message"'));
      expect(functionsSource, contains('"apns-priority"'));
      expect(adminLiveSource, contains('NotificationService.appWideTopic'));
      expect(adminLiveSource, contains('Currently watching'));
      expect(liveSource, contains('recordLiveViewerHeartbeat'));
      expect(liveSource, contains('_activeViewerCount'));
      expect(churchServiceSource, contains('live_stream_viewers'));
      expect(migrationSource, contains('live_stream_viewers'));
      expect(migrationSource, contains('Live viewers insert own presence'));
    });

    test('status owner deletion and video playback are wired', () {
      final feedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final postDetailSource =
          File('lib/screens/community/post_detail_screen.dart')
              .readAsStringSync();
      final playerSource =
          File('lib/widgets/community_video_player.dart').readAsStringSync();
      final communityServiceSource =
          File('lib/services/community_service.dart').readAsStringSync();

      expect(feedSource, contains('CommunityVideoPlayer('));
      expect(feedSource, contains('Delete status?'));
      expect(feedSource, contains('resizeToAvoidBottomInset: true'));
      expect(postDetailSource, contains('CommunityVideoPlayer('));
      expect(playerSource, contains('VideoPlayerController.networkUrl'));
      expect(playerSource, contains('VideoViewType.textureView'));
      expect(playerSource, contains('This video could not be displayed.'));
      expect(playerSource, contains('Retry Video'));
      expect(communityServiceSource, contains('Future<void> deleteStory'));
      expect(communityServiceSource, contains('_storiesTable'));
    });

    test('same church messaging, comments, and localhost auth are hardened',
        () {
      final directMessageSource =
          File('lib/services/direct_message_service.dart').readAsStringSync();
      final inboxSource =
          File('lib/screens/messages/inbox_screen.dart').readAsStringSync();
      final membersSource = File('lib/screens/members/members_list_screen.dart')
          .readAsStringSync();
      final migrationSource = File(
        'supabase/migrations/20260701130000_same_church_messaging_hardening.sql',
      ).readAsStringSync();
      final communityServiceSource =
          File('lib/services/community_service.dart').readAsStringSync();
      final authFlowSource =
          File('lib/services/auth_flow_service.dart').readAsStringSync();
      final profileServiceSource =
          File('lib/services/profile_service.dart').readAsStringSync();
      final avatarMigration = File(
        'supabase/migrations/20260701131000_avatar_storage_access_hardening.sql',
      ).readAsStringSync();
      final releaseDocs =
          File('docs/play_internal_testing_release.md').readAsStringSync();

      expect(directMessageSource, contains('sameChurch'));
      expect(inboxSource, contains('sameChurch || member.allowMessages'));
      expect(membersSource,
          contains('isSameChurch || memberProfile.allowMessages'));
      expect(membersSource, contains('canOverrideProfilePrivacy'));
      expect(migrationSource, contains('other_is_same_church'));
      expect(migrationSource, contains('not other_is_same_church'));
      expect(communityServiceSource,
          contains('Future<List<Map<String, dynamic>>> fetchComments'));
      expect(communityServiceSource, contains('Comment realtime unavailable'));
      expect(profileServiceSource, contains('_imageContentType'));
      expect(avatarMigration, contains("'avatars'"));
      expect(avatarMigration, contains("'image/heif'"));
      expect(avatarMigration, contains('Public read avatars'));
      expect(authFlowSource, contains('http://localhost:3000'));
      expect(releaseDocs, contains('http://localhost:3000/auth/callback'));
    });

    test('profile photos open profiles/viewers instead of inboxes', () {
      final feedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final profileSource =
          File('lib/screens/profile/profile_screen.dart').readAsStringSync();
      final membersSource = File('lib/screens/members/members_list_screen.dart')
          .readAsStringSync();
      final viewerSource =
          File('lib/widgets/profile_photo_viewer.dart').readAsStringSync();

      expect(feedSource, contains('_openPostAuthorProfile'));
      expect(feedSource, contains('showProfilePhotoViewer'));
      expect(feedSource, contains("tooltip: 'Message'"));
      expect(profileSource, contains('_openProfilePhotoPreview'));
      expect(profileSource, contains('onChangePhoto: _isUploading'));
      expect(profileSource, contains('_handlePhotoUpload'));
      expect(membersSource, contains('showProfilePhotoViewer'));
      expect(viewerSource, contains('InteractiveViewer'));
      expect(viewerSource, contains('Profile photo'));
    });

    test('community videos use mobile-safe uploads and inline playback', () {
      final feedSource =
          File('lib/screens/community/community_feed_screen.dart')
              .readAsStringSync();
      final playerSource =
          File('lib/widgets/community_video_player.dart').readAsStringSync();
      final uploadExport =
          File('lib/utils/community_media_upload.dart').readAsStringSync();
      final uploadIo =
          File('lib/utils/community_media_upload_io.dart').readAsStringSync();
      final uploadBytes = File('lib/utils/community_media_upload_bytes.dart')
          .readAsStringSync();
      final migrationSource = File(
        'supabase/migrations/20260701193000_counseling_testimony_media_email_hardening.sql',
      ).readAsStringSync();

      expect(feedSource, contains('uploadCommunityMediaXFile'));
      expect(feedSource, contains('_maxCommunityVideoBytes'));
      expect(feedSource, contains('200MB'));
      expect(feedSource, contains('CommunityVideoPlayer('));
      expect(feedSource, isNot(contains('_InlineCommunityVideoPlayer')));
      expect(playerSource, contains('VideoViewType.textureView'));
      expect(playerSource, contains('VisibilityDetector'));
      expect(playerSource, contains('_VideoPlaybackPositionStore'));
      expect(uploadExport, contains('if (dart.library.io)'));
      expect(uploadIo, contains('uploadMediaFile'));
      expect(uploadBytes, contains('uploadMediaBytes'));
      expect(migrationSource, contains('209715200'));
      expect(migrationSource, contains('video/quicktime'));
    });

    test('counseling requests and testimony notifications are hardened', () {
      final counselingModel =
          File('lib/models/counseling_request_model.dart').readAsStringSync();
      final testimonyService =
          File('lib/services/testimony_service.dart').readAsStringSync();
      final notificationService =
          File('lib/services/notification_service.dart').readAsStringSync();
      final firebaseFunctions = File('functions/index.js').readAsStringSync();
      final migrationSource = File(
        'supabase/migrations/20260701193000_counseling_testimony_media_email_hardening.sql',
      ).readAsStringSync();

      expect(counselingModel, contains("if (id.trim().isNotEmpty) 'id': id"));
      expect(migrationSource, contains('gen_random_uuid'));
      expect(migrationSource, contains('notify_church_on_testimony'));
      expect(migrationSource, contains('trg_notify_church_on_testimony'));
      expect(migrationSource, contains("'testimony'"));
      expect(testimonyService, contains("type: 'testimony'"));
      expect(testimonyService, contains("route: '/testimonies'"));
      expect(notificationService, contains("'testimony'"));
      expect(firebaseFunctions, contains('"testimony"'));
      expect(firebaseFunctions, contains('type === "testimony"'));
    });

    test('password reset and app emails use branded mailer paths', () {
      final authFlowSource =
          File('lib/services/auth_flow_service.dart').readAsStringSync();
      final emailService =
          File('lib/services/email_service.dart').readAsStringSync();
      final mailerSource =
          File('supabase/functions/grace-mailer/index.ts').readAsStringSync();
      final docsSource = File('docs/resend-email-setup.md').readAsStringSync();

      expect(authFlowSource, contains("'action': 'password-reset'"));
      expect(authFlowSource, contains('functions.invoke'));
      expect(authFlowSource, contains('reset-callback'));
      expect(emailService, contains('data-grace-email="true"'));
      expect(emailService, contains('_brandHtmlBody'));
      expect(mailerSource, contains('password-reset'));
      expect(mailerSource, contains('queuedEmailBody'));
      expect(mailerSource, contains('data-grace-email="true"'));
      expect(docsSource, contains('http://localhost:3000'));
      expect(docsSource, contains('app.graceconnect.church://reset-callback/'));
    });
  });
}
