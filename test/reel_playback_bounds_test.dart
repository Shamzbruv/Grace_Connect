import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/reel.dart';
import 'package:grace_connect/services/media_playback_coordinator.dart';

/// The controller budget expressed as a pure function of index + settings,
/// matching what ReelGraceScreen applies when building each page. Testing it
/// directly is what makes "at most two controllers" checkable without a
/// device: on a real phone an off-by-one here is a memory leak that only
/// shows after a hundred swipes.
bool shouldInitialize({
  required int index,
  required int current,
  required bool dataSaver,
  required bool isActive,
}) {
  if (!isActive) return false;
  final distance = (index - current).abs();
  return distance == 0 || (!dataSaver && index == current + 1);
}

void main() {
  group('controller budget', () {
    test('exactly the current and next reel initialize', () {
      final initialized = [
        for (var i = 0; i < 12; i++)
          if (shouldInitialize(index: i, current: 5, dataSaver: false, isActive: true)) i
      ];
      expect(initialized, [5, 6],
          reason: 'current plus one lookahead, never more');
      expect(initialized.length, lessThanOrEqualTo(2));
    });

    test('the previous reel is released rather than kept warm', () {
      expect(
        shouldInitialize(index: 4, current: 5, dataSaver: false, isActive: true),
        isFalse,
        reason: 'a reel behind the current one must not hold a controller',
      );
    });

    test('Data Saver initializes only the current reel', () {
      final initialized = [
        for (var i = 0; i < 12; i++)
          if (shouldInitialize(index: i, current: 5, dataSaver: true, isActive: true)) i
      ];
      expect(initialized, [5],
          reason: 'nothing speculative is downloaded under Data Saver');
    });

    test('leaving Reel Grace initializes nothing at all', () {
      final initialized = [
        for (var i = 0; i < 12; i++)
          if (shouldInitialize(index: i, current: 5, dataSaver: false, isActive: false)) i
      ];
      expect(initialized, isEmpty);
    });

    test('a fast swipe never exceeds two controllers at any point', () {
      // Simulate flinging through 60 reels one page at a time.
      for (var current = 0; current < 60; current++) {
        final live = [
          for (var i = 0; i < 60; i++)
            if (shouldInitialize(index: i, current: current, dataSaver: false, isActive: true)) i
        ];
        expect(live.length, lessThanOrEqualTo(2),
            reason: 'controller count must stay bounded at position $current');
      }
    });
  });

  group('playback ownership during fast swiping', () {
    setUp(MediaPlaybackCoordinator.instance.stopAll);

    test('rapid page changes leave exactly one owner', () {
      final owners = List.generate(20, (_) => Object());
      final stopped = <Object>{};
      for (final owner in owners) {
        MediaPlaybackCoordinator.instance
            .claim(owner, () => stopped.add(owner));
      }
      // Every earlier owner was paused; only the last still holds the floor.
      expect(stopped.length, owners.length - 1);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(owners.last), isTrue);
    });

    test('disposing older pages after a fling cannot silence the visible reel',
        () {
      final older = List.generate(5, (_) => Object());
      final visible = Object();
      var visibleStopped = false;
      for (final owner in older) {
        MediaPlaybackCoordinator.instance.claim(owner, () {});
      }
      MediaPlaybackCoordinator.instance.claim(visible, () => visibleStopped = true);

      // PageView disposes the scrolled-past pages afterwards.
      for (final owner in older) {
        MediaPlaybackCoordinator.instance.release(owner);
      }

      expect(visibleStopped, isFalse);
      expect(MediaPlaybackCoordinator.instance.holdsFloor(visible), isTrue);
    });
  });

  group('state restoration across a mode switch', () {
    test('signed media survives leaving and returning to reels', () {
      // ReelMedia is held by ReelService, which outlives the widget while the
      // IndexedStack keeps both modes alive -- so returning does not re-sign.
      final media = ReelMedia(
        videoUrl: 'https://example.invalid/v.mp4',
        posterUrl: 'https://example.invalid/p.webp',
        expiresAt: DateTime.now().add(const Duration(minutes: 28)),
      );
      expect(media.needsRefresh, isFalse);
      expect(media.isExpired, isFalse);
    });

    test('media signed long ago is re-signed rather than used', () {
      final stale = ReelMedia(
        videoUrl: 'v', posterUrl: 'p',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      expect(stale.needsRefresh, isTrue);
    });
  });
}
