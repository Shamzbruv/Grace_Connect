import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/community_feed_mode.dart';

void main() {
  group('community feed defaults', () {
    test('new and invalid preferences default to Discover', () {
      expect(
        resolveInitialCommunityFeedScope(),
        CommunityFeedMode.discover.storageValue,
      );
      expect(
        resolveInitialCommunityFeedScope(savedScope: 'unexpected'),
        CommunityFeedMode.discover.storageValue,
      );
      expect(
        resolveInitialCommunityFeedScope(
          savedScope: 'custom',
          customChurchIds: const [],
        ),
        CommunityFeedMode.discover.storageValue,
      );
    });

    test('legacy and deliberate valid choices are normalized or preserved', () {
      expect(
        resolveInitialCommunityFeedScope(savedScope: 'all'),
        CommunityFeedMode.discover.storageValue,
      );
      expect(
        resolveInitialCommunityFeedScope(savedScope: 'church'),
        CommunityFeedMode.church.storageValue,
      );
      expect(
        resolveInitialCommunityFeedScope(savedScope: 'following'),
        CommunityFeedMode.following.storageValue,
      );
      expect(
        resolveInitialCommunityFeedScope(
          savedScope: 'custom',
          customChurchIds: const ['church-a'],
        ),
        'custom',
      );
      expect(
        resolveInitialCommunityFeedScope(
          savedScope: 'church',
          forceDiscover: true,
        ),
        CommunityFeedMode.discover.storageValue,
      );
    });
  });

  test('churchless Feed exposes Notifications with an unread badge', () {
    final source = File('lib/screens/community/community_feed_screen.dart')
        .readAsStringSync();

    expect(source, contains('access?.hasActiveChurchMembership'));
    expect(source, contains('if (!hasActiveChurchMembership)'));
    expect(
        source, contains("hasActiveChurchMembership ? profileChurchId : ''"));
    expect(
      source,
      contains(
        'forceDiscover: _hasLimitedAccess || !hasActiveChurchMembership',
      ),
    );
    expect(source, contains('_buildFeedScopeSummary(context, churchId)'));
    expect(
      source,
      contains('final effectiveScope = _effectiveFeedScope(activeChurchId);'),
    );
    expect(source, contains("ValueKey('churchless-feed-notifications')"));
    expect(
      RegExp("Navigator\\.pushNamed\\(context, '/notifications'\\)")
          .allMatches(source)
          .length,
      1,
    );
    expect(source, contains('NotificationService().watchUnreadCount('));
  });
}
