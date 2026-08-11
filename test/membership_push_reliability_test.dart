import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/membership_service.dart';
import 'package:grace_connect/services/notification_service.dart';

void main() {
  group('membership and production push reliability', () {
    test('membership schema errors use a recoverable user-facing state', () {
      final context = MembershipContext.loadFailed(
        status: MembershipLoadStatus.migrationMismatch,
        error: Exception('schema cache unavailable'),
      );

      expect(context.loadErrorTitle, 'Membership Unavailable');
      expect(
          context.loadErrorMessage, contains('No account changes were made'));
      expect(context.loadErrorMessage, isNot(contains('backend update')));
    });

    test(
        'membership fallback verifies current membership instead of profile placeId',
        () {
      final source =
          File('lib/services/membership_service.dart').readAsStringSync();
      expect(source, contains('Duration(minutes: 15)'));
      expect(source, contains(".from('church_memberships')"));
      expect(source, contains("['active', 'pending']"));
      expect(source, contains("churchStatus != 'approved'"));
      expect(
        source,
        isNot(
            contains("membershipStatus: churchId.isEmpty ? 'none' : 'active'")),
      );
    });

    test('Bible streak reminders route directly to the Bible', () {
      expect(NotificationService.normalizeRoute('/bible'), '/bible');
    });

    test('mobile client registers refreshed FCM tokens and keeps fallback', () {
      final source =
          File('lib/services/notification_service.dart').readAsStringSync();

      expect(source, contains('FirebaseMessaging.instance'));
      expect(source, contains('onTokenRefresh.listen'));
      expect(source, contains("'register_push_device'"));
      expect(source, contains("'unregister_push_device'"));
      expect(source, contains('graceconnect_registered_delivery_v1'));
      expect(source, contains("'p_installation_id'"));
      expect(source, contains("'p_unregister_secret'"));
      expect(source, contains('push_subscribed_topics_v2'));
      expect(source, contains('_unsubscribeStoredTopicsOutside'));
      expect(source, contains("'can_manage_church_members'"));
      expect(source, contains('await _canManageChurchMembers(cleanChurchId)'));
      expect(source, isNot(contains("'manageroles'")));
      expect(source, contains('_signedOutStartupCleanup'));
      expect(source, contains('_supabase.auth.currentUser == null'));
      expect(source, contains('bible_streak_reminder'));
      expect(source, contains('subscribeToTopic'));
    });

    test('database and Edge push paths support registered installations', () {
      final migration = File(
        'supabase/migrations/20260805170000_membership_and_push_delivery_reliability.sql',
      ).readAsStringSync();
      final edgeShared =
          File('supabase/functions/_shared/grace.ts').readAsStringSync();

      expect(migration, contains('public.push_device_registrations'));
      expect(migration, contains('public.register_push_device'));
      expect(migration, contains('public.unregister_push_device'));
      expect(migration, contains('p_installation_id uuid'));
      expect(migration, contains('md5(clean_unregister_secret)'));
      expect(migration, contains('allowed_requested_topics'));
      expect(
          migration, contains("requested_topic = 'user_' || actor_id::text"));
      expect(migration, contains('public.can_manage_church_members'));
      expect(migration, contains("'approvemembers'"));
      expect(migration, isNot(contains('unnest(a.profile_roles)')));
      expect(migration, contains('sync_active_membership_profile'));
      expect(migration, contains('set uid = u.id::text'));
      expect(migration, contains('collision.uid = u.id::text'));
      expect(
        migration,
        contains('cm.user_id = u.id or u.uid = cm.user_id::text'),
      );
      expect(
        migration,
        isNot(contains('church_member_roles_membership_id_role_name_key')),
      );
      expect(migration, contains('claim_membership_push_delivery'));

      expect(edgeShared, contains('push_device_registrations'));
      expect(edgeShared, contains('REGISTERED_DELIVERY_TOPIC'));
      expect(edgeShared, contains('condition:'));
      expect(edgeShared, contains('UNREGISTERED'));
      expect(edgeShared, contains('Promise.allSettled'));
      expect(edgeShared, contains('registryOnlyTopic'));
      expect(edgeShared,
          contains('.range(from, from + registrationPageSize - 1)'));
      expect(edgeShared, isNot(contains('.gte("last_seen_at"')));
      expect(edgeShared, contains('bible_streak_reminder'));
    });

    test('membership request and approval pushes are idempotent', () {
      final edge = File(
        'supabase/functions/send-membership-request-push/index.ts',
      ).readAsStringSync();
      final reviewScreen = File(
        'lib/screens/admin/membership_requests_screen.dart',
      ).readAsStringSync();

      expect(edge, contains('claim_membership_push_delivery'));
      expect(edge, contains('membership_request_received'));
      expect(edge, contains('membership_approved'));
      expect(edge, contains('deduplicated: true'));
      expect(reviewScreen, contains('sendMembershipApprovedPush'));
    });

    test('global in-app notification fan-out is paginated and chunked', () {
      final edgeShared =
          File('supabase/functions/_shared/grace.ts').readAsStringSync();
      expect(edgeShared, contains('const userIds = new Set<string>()'));
      expect(edgeShared, contains('.range(from, from + pageSize - 1)'));
      expect(edgeShared, contains('rows.slice(offset, offset + pageSize)'));
    });
  });
}
