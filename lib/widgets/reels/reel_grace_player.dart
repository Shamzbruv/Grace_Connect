import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/reel.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/reel_service.dart';

/// One reel's video surface.
///
/// The poster is painted immediately and stays underneath the video, so a
/// swipe never lands on a black rectangle while a controller initializes.
/// Only reels the coordinator marks active initialize at all; everything else
/// is poster-only, which is what keeps memory bounded during fast swiping.
class ReelGracePlayer extends StatefulWidget {
  const ReelGracePlayer({
    super.key,
    required this.reel,
    required this.service,
    required this.isCurrent,
    required this.shouldInitialize,
    required this.muted,
    this.onPlaybackProgress,
    this.onCompleted,
  });

  final Reel reel;
  final ReelService service;

  /// The reel on screen. Only this one plays audibly.
  final bool isCurrent;

  /// Whether a controller may exist at all. False for distant reels, and for
  /// the next reel when Data Saver is on.
  final bool shouldInitialize;
  final bool muted;
  final void Function(Duration position, Duration duration)? onPlaybackProgress;
  final VoidCallback? onCompleted;

  @override
  State<ReelGracePlayer> createState() => _ReelGracePlayerState();
}

class _ReelGracePlayerState extends State<ReelGracePlayer> {
  VideoPlayerController? _controller;
  String? _controllerUrl;
  bool _initializing = false;
  bool _failed = false;
  bool _userPaused = false;
  bool _completedReported = false;

  @override
  void initState() {
    super.initState();
    if (widget.shouldInitialize) unawaited(_prepare());
  }

  @override
  void didUpdateWidget(covariant ReelGracePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.shouldInitialize) {
      _releaseController();
      return;
    }
    if (_controller == null && !_initializing) {
      unawaited(_prepare());
      return;
    }
    if (widget.isCurrent != oldWidget.isCurrent) {
      widget.isCurrent ? _play() : _pause();
    }
    if (widget.muted != oldWidget.muted) {
      unawaited(_controller?.setVolume(widget.muted ? 0 : 1));
    }
  }

  Future<void> _prepare() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    try {
      var media = widget.service.cachedMedia(widget.reel.id);
      // A URL that lapsed while this reel sat off screen is re-signed rather
      // than surfaced as a playback failure.
      if (media == null || media.needsRefresh) {
        media = await widget.service.refreshMedia(widget.reel.id);
      }
      final url = media?.videoUrl;
      if (url == null || !mounted) {
        if (mounted) setState(() => _failed = url == null);
        return;
      }

      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || !widget.shouldInitialize) {
        unawaited(controller.dispose());
        return;
      }
      await controller.setLooping(false);
      await controller.setVolume(widget.muted ? 0 : 1);
      controller.addListener(_onTick);
      setState(() {
        _controller = controller;
        _controllerUrl = url;
        _failed = false;
      });
      if (widget.isCurrent && !_userPaused) _play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _initializing = false;
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final position = controller.value.position;
    final duration = controller.value.duration;
    widget.onPlaybackProgress?.call(position, duration);
    if (!_completedReported &&
        duration > Duration.zero &&
        position >= duration - const Duration(milliseconds: 250)) {
      _completedReported = true;
      widget.onCompleted?.call();
    }
  }

  void _play() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Claim the floor so any feed video or other reel stops first.
    MediaPlaybackCoordinator.instance.claim(this, () {
      if (mounted) controller.pause();
    });
    controller.play();
  }

  void _pause() {
    _controller?.pause();
    MediaPlaybackCoordinator.instance.release(this);
  }

  void _releaseController() {
    final controller = _controller;
    if (controller == null) return;
    MediaPlaybackCoordinator.instance.release(this);
    controller.removeListener(_onTick);
    _controller = null;
    _controllerUrl = null;
    _completedReported = false;
    unawaited(controller.dispose());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    MediaPlaybackCoordinator.instance.release(this);
    controller?.removeListener(_onTick);
    unawaited(controller?.dispose());
    super.dispose();
  }

  void togglePlayPause() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      _pause();
    } else {
      _userPaused = false;
      _play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.service.cachedMedia(widget.reel.id);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tap toggles playback. Owned here because this is where the
      // controller lives; reaching in from the page above was fragile.
      onTap: ready ? togglePlayPause : null,
      child: Stack(
      fit: StackFit.expand,
      children: [
        // Poster underneath at all times: it is what the viewer sees on the
        // first frame of a swipe, and what remains if playback fails.
        if (media?.posterUrl != null)
          CachedNetworkImage(
            imageUrl: media!.posterUrl!,
            fit: BoxFit.cover,
            // Keyed by reel id so a re-signed URL does not re-download it.
            cacheKey: 'reel_poster_${widget.reel.id}',
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
          )
        else
          const ColoredBox(color: Colors.black),
        if (ready)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        if (!ready && !_failed && widget.shouldInitialize)
          const Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
          ),
        if (_failed)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_outlined, color: Colors.white70, size: 34),
                const SizedBox(height: 10),
                const Text('This reel could not play.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _failed = false);
                    unawaited(_prepare());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (ready && !controller.value.isPlaying && widget.isCurrent)
          const Center(
            child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white70),
          ),
      ],
      ),
    );
  }

  String? get debugControllerUrl => _controllerUrl;
}
