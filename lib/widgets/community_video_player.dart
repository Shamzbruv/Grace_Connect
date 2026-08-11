import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// A lifecycle-safe network video player shared by feed posts, post detail,
/// full-screen media, and statuses.
///
/// It attaches the texture before autoplay (avoiding audio-only startup on
/// Android), pauses while off-screen/backgrounded, survives async URL races,
/// exposes buffering/error states, and remembers the last useful position.
class CommunityVideoPlayer extends StatefulWidget {
  const CommunityVideoPlayer({
    super.key,
    required this.mediaUrl,
    this.fit = BoxFit.contain,
    this.autoPlay = false,
    this.looping = true,
    this.showControls = true,
  });

  final String mediaUrl;
  final BoxFit fit;
  final bool autoPlay;
  final bool looping;
  final bool showControls;

  @override
  State<CommunityVideoPlayer> createState() => _CommunityVideoPlayerState();
}

class _CommunityVideoPlayerState extends State<CommunityVideoPlayer>
    with WidgetsBindingObserver {
  static const _initializeTimeout = Duration(seconds: 25);

  final Key _visibilityKey = UniqueKey();
  VideoPlayerController? _controller;
  String? _controllerMediaUrl;
  Object? _error;
  bool _initializing = true;
  bool _visible = false;
  bool _appActive = false;
  bool _resumeWhenVisible = false;
  bool _lastPlaying = false;
  bool _lastBuffering = false;
  String? _lastErrorDescription;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant CommunityVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      unawaited(_initialize());
    } else if (oldWidget.looping != widget.looping) {
      unawaited(_controller?.setLooping(widget.looping));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_resumeWhenVisible && _visible) unawaited(_play());
      return;
    }
    unawaited(_pause(rememberToResume: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadGeneration++;
    final controller = _controller;
    final controllerMediaUrl = _controllerMediaUrl;
    _controller = null;
    _controllerMediaUrl = null;
    if (controller != null) {
      controller.removeListener(_onControllerValueChanged);
      _rememberPosition(controller, controllerMediaUrl);
      unawaited(controller.pause().catchError((_) {}));
      unawaited(controller.dispose().catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _initialize() async {
    final generation = ++_loadGeneration;
    _resumeWhenVisible = false;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }

    final previous = _controller;
    final previousMediaUrl = _controllerMediaUrl;
    _controller = null;
    _controllerMediaUrl = null;
    if (previous != null) {
      previous.removeListener(_onControllerValueChanged);
      _rememberPosition(previous, previousMediaUrl);
      await previous.pause().catchError((_) {});
      await previous.dispose().catchError((_) {});
    }

    final uri = Uri.tryParse(widget.mediaUrl.trim());
    if (uri == null || !uri.hasScheme) {
      _finishWithError(generation, const FormatException('Invalid video URL.'));
      return;
    }

    final controller = VideoPlayerController.networkUrl(
      uri,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
      viewType: VideoViewType.textureView,
    );

    try {
      await controller.initialize().timeout(_initializeTimeout);
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }

      final size = controller.value.size;
      if (size.width <= 0 || size.height <= 0) {
        throw StateError(
            'The video does not contain a displayable video track.');
      }

      await controller.setLooping(widget.looping);
      await controller.setVolume(1);
      final remembered =
          await _VideoPlaybackPositionStore.read(widget.mediaUrl);
      if (remembered > Duration.zero &&
          remembered < controller.value.duration - const Duration(seconds: 2)) {
        await controller.seekTo(remembered);
      }

      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _controllerMediaUrl = widget.mediaUrl;
      _lastPlaying = controller.value.isPlaying;
      _lastBuffering = controller.value.isBuffering;
      _lastErrorDescription = controller.value.errorDescription;
      controller.addListener(_onControllerValueChanged);
      setState(() => _initializing = false);

      // Waiting until the texture is in the widget tree prevents playback from
      // beginning with audio before Android has a surface for the first frame.
      await WidgetsBinding.instance.endOfFrame;
      if (widget.autoPlay && mounted && generation == _loadGeneration) {
        if (_appActive && _visible) {
          await _play();
        } else {
          // Initialization can finish after Android has removed the rendering
          // surface. Defer autoplay until both the app and this widget are
          // visible so audio cannot start behind a black frame.
          _resumeWhenVisible = true;
        }
      }
    } catch (error) {
      if (identical(_controller, controller)) {
        controller.removeListener(_onControllerValueChanged);
        _controller = null;
        _controllerMediaUrl = null;
      }
      await controller.dispose().catchError((_) {});
      _finishWithError(generation, error);
    }
  }

  void _finishWithError(int generation, Object error) {
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _controller = null;
      _initializing = false;
      _error = error;
    });
  }

  void _onControllerValueChanged() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.isPlaying == _lastPlaying &&
        value.isBuffering == _lastBuffering &&
        value.errorDescription == _lastErrorDescription) {
      return;
    }
    _lastPlaying = value.isPlaying;
    _lastBuffering = value.isBuffering;
    _lastErrorDescription = value.errorDescription;
    if (value.hasError) {
      _resumeWhenVisible = false;
      // A decoder can fail after initialization. Stop the audio immediately so
      // an Android surface/codec failure cannot leave a black frame playing
      // sound behind the retry state.
      unawaited(controller.pause().catchError((_) {}));
    }
    setState(() {
      if (value.hasError) _error = value.errorDescription;
    });
  }

  Future<void> _play() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.hasError ||
        _error != null ||
        !_appActive ||
        !_visible) {
      return;
    }
    try {
      final duration = controller.value.duration;
      if (duration > Duration.zero &&
          duration - controller.value.position <
              const Duration(milliseconds: 500)) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _resumeWhenVisible = true;
    } catch (error) {
      _resumeWhenVisible = false;
      await controller.pause().catchError((_) {});
      if (mounted && identical(_controller, controller)) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _pause({bool rememberToResume = false}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (rememberToResume) _resumeWhenVisible = controller.value.isPlaying;
    _rememberPosition(controller, _controllerMediaUrl);
    await controller.pause().catchError((_) {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _resumeWhenVisible = false;
      await _pause();
    } else {
      await _play();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final nextVisible = info.visibleFraction >= 0.15;
    if (_visible == nextVisible) return;
    _visible = nextVisible;
    if (!nextVisible) {
      unawaited(_pause(rememberToResume: true));
    } else if (_resumeWhenVisible) {
      unawaited(_play());
    }
  }

  void _rememberPosition(
    VideoPlayerController controller,
    String? mediaUrl,
  ) {
    if (!controller.value.isInitialized) return;
    final cleanMediaUrl = mediaUrl?.trim() ?? '';
    if (cleanMediaUrl.isEmpty) return;
    _VideoPlaybackPositionStore.remember(
      cleanMediaUrl,
      controller.value.position,
      controller.value.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null &&
        controller.value.isInitialized &&
        !controller.value.hasError &&
        _error == null &&
        controller.value.size.width > 0 &&
        controller.value.size.height > 0;

    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _onVisibilityChanged,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (ready)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.showControls ? _togglePlayback : null,
                child: Center(
                  child: FittedBox(
                    fit: widget.fit,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              )
            else
              _VideoLoadState(
                initializing: _initializing,
                error: _error,
                onRetry: _initialize,
              ),
            if (ready && widget.showControls && !controller.value.isPlaying)
              Center(
                child: IconButton.filled(
                  tooltip: 'Play video',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: Colors.black,
                    fixedSize: const Size(58, 58),
                  ),
                  onPressed: _togglePlayback,
                  icon: const Icon(Icons.play_arrow, size: 34),
                ),
              ),
            if (ready && controller.value.isBuffering)
              const Center(
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            if (ready && widget.showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF8CCBFF),
                    bufferedColor: Colors.white54,
                    backgroundColor: Colors.white24,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoLoadState extends StatelessWidget {
  const _VideoLoadState({
    required this.initializing,
    required this.error,
    required this.onRetry,
  });

  final bool initializing;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white, size: 44),
            const SizedBox(height: 10),
            const Text(
              'This video could not be displayed. Check your connection or try again.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              const Text(
                'The file may use a video format this device cannot decode.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlaybackPositionStore {
  static final Map<String, Duration> _positions = {};

  static Future<Duration> read(String url) async {
    final memory = _positions[url];
    if (memory != null) return memory;
    try {
      final preferences = await SharedPreferences.getInstance();
      final milliseconds = preferences.getInt(_key(url)) ?? 0;
      final position = Duration(milliseconds: milliseconds);
      _positions[url] = position;
      return position;
    } catch (_) {
      // Playback must not fail just because position persistence is
      // temporarily unavailable.
      return Duration.zero;
    }
  }

  static void remember(String url, Duration position, Duration duration) {
    final normalized = duration > Duration.zero &&
            duration - position < const Duration(seconds: 2)
        ? Duration.zero
        : position;
    _positions[url] = normalized;
    unawaited(() async {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setInt(_key(url), normalized.inMilliseconds);
      } catch (_) {
        // The in-memory position still keeps route-to-route playback stable.
      }
    }());
  }

  static String _key(String url) {
    final encoded = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return 'community_video_position_$encoded';
  }
}
