import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
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
    this.thumbnailUrl,
    this.fit = BoxFit.contain,
    this.autoPlay = false,
    this.looping = true,
    this.showControls = true,
  });

  final String mediaUrl;
  final String? thumbnailUrl;
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
  static const _offscreenReleaseDelay = Duration(seconds: 18);
  static final _initializationGate = _VideoInitializationGate(maxConcurrent: 2);
  static final _playbackCoordinator = _VideoPlaybackCoordinator();

  final Key _visibilityKey = UniqueKey();
  late final int _playbackOwnerId;
  VideoPlayerController? _controller;
  String? _controllerMediaUrl;
  Object? _error;
  bool _initializing = false;
  bool _posterVisible = true;
  bool _visible = false;
  bool _appActive = false;
  bool _resumeWhenVisible = false;
  bool _lastPlaying = false;
  bool _lastBuffering = false;
  String? _lastErrorDescription;
  int _loadGeneration = 0;
  Timer? _offscreenReleaseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playbackOwnerId = identityHashCode(this);
    _playbackCoordinator.register(
      _playbackOwnerId,
      () => _pause(rememberToResume: false),
    );
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didUpdateWidget(covariant CommunityVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _posterVisible = true;
      unawaited(() async {
        await _releaseController();
        if (_visible) await _initialize();
      }());
    } else if (oldWidget.looping != widget.looping) {
      unawaited(_controller?.setLooping(widget.looping));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_visible && _controller == null) {
        unawaited(_initialize());
      } else if (_resumeWhenVisible && _visible) {
        unawaited(_play());
      }
      return;
    }
    unawaited(_pause(rememberToResume: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackCoordinator.unregister(_playbackOwnerId);
    _offscreenReleaseTimer?.cancel();
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
    if (_initializing ||
        (_controller != null && _controllerMediaUrl == widget.mediaUrl)) {
      return;
    }
    final generation = ++_loadGeneration;
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
      final initializationStarted = await _initializationGate.run(() async {
        // A feed card can leave the viewport while waiting for one of the two
        // initialization slots. Recheck all state inside the gate so a stale
        // card never starts network or decoder work when its turn arrives.
        if (!mounted ||
            generation != _loadGeneration ||
            !_visible ||
            !_appActive) {
          return false;
        }
        await controller.initialize().timeout(_initializeTimeout);
        return true;
      });
      if (!initializationStarted) {
        await controller.dispose().catchError((_) {});
        if (mounted && generation == _loadGeneration) {
          setState(() => _initializing = false);
        }
        return;
      }
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
      // Keep the poster over an initialized, paused texture. Some Android
      // decoders expose a black texture until playback advances; revealing it
      // here would bring back the black-card bug even though initialization
      // succeeded. The listener removes the poster only after playback has
      // advanced to a real frame.
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
    final canRevealPlaybackFrame = _posterVisible &&
        value.isPlaying &&
        value.position > const Duration(milliseconds: 30);
    if (value.isPlaying == _lastPlaying &&
        value.isBuffering == _lastBuffering &&
        value.errorDescription == _lastErrorDescription &&
        !canRevealPlaybackFrame) {
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
      if (canRevealPlaybackFrame) _posterVisible = false;
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
      _playbackCoordinator.focus(_playbackOwnerId);
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
    if (controller == null || !controller.value.isInitialized) {
      if (!rememberToResume) _resumeWhenVisible = false;
      return;
    }
    _resumeWhenVisible = rememberToResume ? controller.value.isPlaying : false;
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
    final nextVisible = info.visibleFraction >= 0.01;
    if (_visible == nextVisible) return;
    _visible = nextVisible;
    if (!nextVisible) {
      unawaited(_pause(rememberToResume: true));
      _offscreenReleaseTimer?.cancel();
      _offscreenReleaseTimer = Timer(
        _offscreenReleaseDelay,
        () => unawaited(_releaseController()),
      );
    } else {
      _offscreenReleaseTimer?.cancel();
      if (_controller == null) {
        if (widget.autoPlay) _resumeWhenVisible = true;
        unawaited(_initialize());
      } else if (_resumeWhenVisible) {
        unawaited(_play());
      }
    }
  }

  Future<void> _releaseController() async {
    _loadGeneration++;
    final controller = _controller;
    final mediaUrl = _controllerMediaUrl;
    if (controller == null) {
      if (mounted && _initializing) {
        setState(() {
          _posterVisible = true;
          _initializing = false;
        });
      }
      return;
    }
    _controller = null;
    _controllerMediaUrl = null;
    controller.removeListener(_onControllerValueChanged);
    _rememberPosition(controller, mediaUrl);
    await controller.pause().catchError((_) {});
    await controller.dispose().catchError((_) {});
    if (mounted) {
      setState(() {
        _posterVisible = true;
        _initializing = false;
      });
    }
  }

  Future<void> _startFromPoster() async {
    _resumeWhenVisible = true;
    if (_controller == null) await _initialize();
    if (_visible) await _play();
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
            else if (_error != null)
              _VideoLoadState(
                initializing: _initializing,
                error: _error,
                thumbnailUrl: widget.thumbnailUrl,
                fit: widget.fit,
                onRetry: _initialize,
                onPlay: _startFromPoster,
              )
            else
              _VideoPoster(
                thumbnailUrl: widget.thumbnailUrl,
                fit: widget.fit,
                loading: _initializing,
                onPlay: _startFromPoster,
              ),
            if (ready && _posterVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: _VideoPoster(
                    thumbnailUrl: widget.thumbnailUrl,
                    fit: widget.fit,
                    loading: controller.value.isPlaying,
                    onPlay: _startFromPoster,
                    showPlayButton: false,
                  ),
                ),
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
    required this.thumbnailUrl,
    required this.fit,
    required this.onRetry,
    required this.onPlay,
  });

  final bool initializing;
  final Object? error;
  final String? thumbnailUrl;
  final BoxFit fit;
  final VoidCallback onRetry;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    if (initializing) {
      return _VideoPoster(
        thumbnailUrl: thumbnailUrl,
        fit: fit,
        loading: true,
        onPlay: onPlay,
      );
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

class _VideoPoster extends StatelessWidget {
  const _VideoPoster({
    required this.thumbnailUrl,
    required this.fit,
    required this.loading,
    required this.onPlay,
    this.showPlayButton = true,
  });

  final String? thumbnailUrl;
  final BoxFit fit;
  final bool loading;
  final VoidCallback onPlay;
  final bool showPlayButton;

  @override
  Widget build(BuildContext context) {
    final cleanThumbnailUrl = thumbnailUrl?.trim() ?? '';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cleanThumbnailUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: cleanThumbnailUrl,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 120),
            placeholder: (_, __) => const ColoredBox(color: Colors.black),
            errorWidget: (_, __, ___) => const _GenericVideoPoster(),
          )
        else
          const _GenericVideoPoster(),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black12, Colors.black45],
            ),
          ),
        ),
        if (showPlayButton && !loading)
          Center(
            child: IconButton.filled(
              tooltip: 'Play video',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.92),
                foregroundColor: Colors.black,
                fixedSize: const Size(58, 58),
              ),
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow, size: 34),
            ),
          ),
        if (loading)
          const Positioned(
            right: 12,
            bottom: 12,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
      ],
    );
  }
}

class _GenericVideoPoster extends StatelessWidget {
  const _GenericVideoPoster();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF151B26),
      child: Center(
        child:
            Icon(Icons.video_library_outlined, color: Colors.white54, size: 46),
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

class _VideoInitializationGate {
  _VideoInitializationGate({required this.maxConcurrent});

  final int maxConcurrent;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<T> run<T>(Future<T> Function() action) async {
    if (_active >= maxConcurrent) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    try {
      return await action();
    } finally {
      if (_waiters.isNotEmpty) {
        // Hand the occupied slot directly to the oldest waiter.
        _waiters.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }
}

class _VideoPlaybackCoordinator {
  final Map<int, Future<void> Function()> _pauseCallbacks = {};

  void register(int ownerId, Future<void> Function() pause) {
    _pauseCallbacks[ownerId] = pause;
  }

  void unregister(int ownerId) {
    _pauseCallbacks.remove(ownerId);
  }

  void focus(int ownerId) {
    for (final entry in _pauseCallbacks.entries.toList(growable: false)) {
      if (entry.key != ownerId) unawaited(entry.value());
    }
  }
}
