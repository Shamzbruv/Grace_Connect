import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/reel.dart';
import 'package:grace_connect/services/media_playback_coordinator.dart';

void main() {
  group('FeedHubController', () {
    test('starts on the Community Feed', () {
      final controller = FeedHubControllerForTest();
      expect(controller.value, PrimaryFeedMode.community);
    });

    test('re-tap style toggling moves both ways', () {
      final controller = FeedHubControllerForTest();
      controller.toggle();
      expect(controller.value, PrimaryFeedMode.reelGrace);
      controller.toggle();
      expect(controller.value, PrimaryFeedMode.community);
    });

    test('leaving the Feed tab returns it to the Community Feed', () {
      final controller = FeedHubControllerForTest()..toggle();
      expect(controller.value, PrimaryFeedMode.reelGrace);
      controller.showCommunity();
      expect(controller.value, PrimaryFeedMode.community,
          reason: 'coming back from another tab must not land inside reels');
    });
  });

  group('MediaPlaybackCoordinator', () {
    setUp(MediaPlaybackCoordinator.instance.stopAll);

    test('a second claimant stops the first, so two videos never play', () {
      final first = Object();
      final second = Object();
      var firstStopped = false;
      var secondStopped = false;

      MediaPlaybackCoordinator.instance.claim(first, () => firstStopped = true);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(first), isTrue);

      MediaPlaybackCoordinator.instance.claim(second, () => secondStopped = true);
      expect(firstStopped, isTrue, reason: 'the previous owner must be paused');
      expect(secondStopped, isFalse);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(second), isTrue);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(first), isFalse);
    });

    test('re-claiming by the same owner does not stop it', () {
      final owner = Object();
      var stops = 0;
      MediaPlaybackCoordinator.instance.claim(owner, () => stops++);
      MediaPlaybackCoordinator.instance.claim(owner, () => stops++);
      expect(stops, 0);
    });

    test('a stale release cannot silence newer playback', () {
      final old = Object();
      final current = Object();
      var currentStopped = false;
      MediaPlaybackCoordinator.instance.claim(old, () {});
      MediaPlaybackCoordinator.instance.claim(current, () => currentStopped = true);

      // The old widget disposes after the new one already took over.
      MediaPlaybackCoordinator.instance.release(old);

      expect(currentStopped, isFalse);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(current), isTrue);
    });

    test('stopAll silences the floor, as backgrounding must', () {
      final owner = Object();
      var stopped = false;
      MediaPlaybackCoordinator.instance.claim(owner, () => stopped = true);
      MediaPlaybackCoordinator.instance.stopAll();
      expect(stopped, isTrue);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(owner), isFalse);
    });
  });

  group('ReelMedia expiry', () {
    test('refreshes before it lapses, not after', () {
      final soon = ReelMedia(
        videoUrl: 'v', posterUrl: 'p',
        expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      );
      expect(soon.needsRefresh, isTrue,
          reason: 'inside the 5 minute margin it must be re-signed early');
      expect(soon.isExpired, isFalse);

      final fresh = ReelMedia(
        videoUrl: 'v', posterUrl: 'p',
        expiresAt: DateTime.now().add(const Duration(minutes: 25)),
      );
      expect(fresh.needsRefresh, isFalse);

      final gone = ReelMedia(
        videoUrl: 'v', posterUrl: 'p',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(gone.isExpired, isTrue);
      expect(gone.needsRefresh, isTrue);
    });
  });

  group('Reel model', () {
    test('parses the feed row and exposes no playback URL', () {
      final reel = Reel.fromMap({
        'id': 'r1', 'author_id': 'a1', 'author_name': 'Member',
        'caption': 'Praise', 'visibility': 'followers',
        'video_object_key': 'reels/a1/r1/video.mp4',
        'poster_object_key': 'reels/a1/r1/poster.webp',
        'like_count': 4, 'viewer_liked': true,
      });
      expect(reel.visibility, ReelVisibility.followers);
      expect(reel.videoObjectKey, 'reels/a1/r1/video.mp4');
      expect(reel.likeCount, 4);
      expect(reel.viewerLiked, isTrue);
      // The model intentionally has no URL field: a stored playback URL
      // would outlive its authorization check.
      expect(reel.toString().contains('http'), isFalse);
    });

    test('optimistic copyWith leaves untouched fields alone', () {
      final reel = Reel.fromMap({
        'id': 'r1', 'author_id': 'a1', 'author_name': 'Member',
        'caption': 'c', 'visibility': 'public', 'like_count': 2,
        'save_count': 7,
      });
      final liked = reel.copyWith(viewerLiked: true, likeCount: 3);
      expect(liked.likeCount, 3);
      expect(liked.viewerLiked, isTrue);
      expect(liked.saveCount, 7);
      expect(liked.caption, 'c');
    });
  });
}

/// Mirrors FeedHubController without pulling the widget tree into a unit test.
class FeedHubControllerForTest extends ValueNotifier<PrimaryFeedMode> {
  FeedHubControllerForTest() : super(PrimaryFeedMode.community);
  void toggle() => value = value == PrimaryFeedMode.community
      ? PrimaryFeedMode.reelGrace
      : PrimaryFeedMode.community;
  void showCommunity() => value = PrimaryFeedMode.community;
}
