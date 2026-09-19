import 'package:flutter/foundation.dart';

/// One owner of audible playback across the whole app.
///
/// Community Feed video and Reel Grace are separate widget trees that can be
/// alive at the same time -- the Feed is deliberately kept in memory while
/// Reel Grace is showing. Without a shared owner, a feed video and a reel can
/// both play, which is heard as two soundtracks at once. Anything that starts
/// playing claims the floor here first, and whoever held it is told to stop.
class MediaPlaybackCoordinator {
  MediaPlaybackCoordinator._();

  static final MediaPlaybackCoordinator instance = MediaPlaybackCoordinator._();

  Object? _owner;
  VoidCallback? _stopCurrent;

  /// Claims audible playback for [owner]. The previous owner is paused.
  void claim(Object owner, VoidCallback stop) {
    if (identical(_owner, owner)) {
      _stopCurrent = stop;
      return;
    }
    final previousStop = _stopCurrent;
    _owner = owner;
    _stopCurrent = stop;
    previousStop?.call();
  }

  /// Releases the floor if [owner] still holds it. Releasing after another
  /// widget has claimed it must not stop that newer playback.
  void release(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _stopCurrent = null;
  }

  /// Stops whatever is playing -- used when the app backgrounds or the host
  /// surface stops being visible.
  void stopAll() {
    final stop = _stopCurrent;
    _owner = null;
    _stopCurrent = null;
    stop?.call();
  }

  bool holdsFloor(Object owner) => identical(_owner, owner);
}
