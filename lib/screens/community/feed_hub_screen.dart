import 'package:flutter/material.dart';

import '../../models/reel.dart';
import '../../services/media_playback_coordinator.dart';
import '../reels/reel_grace_screen.dart';
import 'community_feed_screen.dart';

/// Host for the Feed destination's two modes.
///
/// An IndexedStack rather than swapping children: the Community Feed keeps
/// its scroll position, loaded posts and in-flight state while Reel Grace is
/// showing, so toggling back is instant and does not re-query. Reel Grace is
/// likewise kept alive so returning to it lands on the same reel.
class FeedHubScreen extends StatefulWidget {
  const FeedHubScreen({
    super.key,
    this.showFindChurchAction = false,
    this.controller,
  });

  final bool showFindChurchAction;
  final FeedHubController? controller;

  @override
  State<FeedHubScreen> createState() => _FeedHubScreenState();
}

/// Lets the tab shell toggle modes without reaching into the widget tree.
class FeedHubController extends ValueNotifier<PrimaryFeedMode> {
  FeedHubController() : super(PrimaryFeedMode.community);

  void toggle() => value = value == PrimaryFeedMode.community
      ? PrimaryFeedMode.reelGrace
      : PrimaryFeedMode.community;

  void showCommunity() => value = PrimaryFeedMode.community;
}

class _FeedHubScreenState extends State<FeedHubScreen> {
  late final FeedHubController _controller =
      widget.controller ?? FeedHubController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onModeChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onModeChanged);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onModeChanged() {
    // Leaving Reel Grace must silence it immediately rather than waiting for
    // a visibility callback that may not arrive while it stays mounted.
    if (_controller.value == PrimaryFeedMode.community) {
      MediaPlaybackCoordinator.instance.stopAll();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mode = _controller.value;
    return IndexedStack(
      index: mode == PrimaryFeedMode.community ? 0 : 1,
      children: [
        CommunityFeedScreen(
          showBottomMenu: false,
          showFindChurchAction: widget.showFindChurchAction,
        ),
        ReelGraceScreen(isActive: mode == PrimaryFeedMode.reelGrace),
      ],
    );
  }
}
