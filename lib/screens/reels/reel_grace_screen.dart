import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../models/reel.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/reel_analytics_service.dart';
import '../../services/reel_service.dart';
import '../../widgets/reels/reel_grace_player.dart';

/// Full-screen vertical reel feed.
///
/// Controller budget: the current reel, plus the next one so a swipe starts
/// instantly. Everything else is poster-only. Under Data Saver only the
/// current reel initializes at all, so nothing speculative is downloaded.
class ReelGraceScreen extends StatefulWidget {
  const ReelGraceScreen({super.key, required this.isActive});

  /// Whether Reel Grace is the visible mode. When false, playback stops --
  /// the widget stays alive so the feed position survives a mode switch.
  final bool isActive;

  @override
  State<ReelGraceScreen> createState() => _ReelGraceScreenState();
}

class _ReelGraceScreenState extends State<ReelGraceScreen>
    with WidgetsBindingObserver {
  final ReelService _service = ReelService();
  final PageController _pageController = PageController();
  final List<Reel> _reels = [];
  final Set<String> _seenIds = {};
  final Map<String, DateTime> _impressionAt = {};
  final Set<String> _quartilesFired = {};

  Map<String, dynamic>? _cursor;
  String _mode = 'discover';
  int _index = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _muted = false;
  bool _dataSaver = false;
  bool _visible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadPreferences());
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Backgrounding must silence playback immediately, not on the next
      // frame after the app is already gone from view.
      MediaPlaybackCoordinator.instance.stopAll();
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ReelGraceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      MediaPlaybackCoordinator.instance.stopAll();
      setState(() {});
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dataSaver = prefs.getBool('data_saver') ?? false;
      _muted = prefs.getBool('reel_grace_muted') ?? false;
    });
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _seenIds.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _service.fetchFeed(mode: _mode, limit: 12);
      if (!mounted) return;
      final fresh = page.reels.where((r) => _seenIds.add(r.id)).toList();
      setState(() {
        _reels
          ..clear()
          ..addAll(fresh);
        _cursor = page.nextCursor;
        _loading = false;
        _index = 0;
      });
      await _ensureMediaAround(0);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _cursor == null) return;
    _loadingMore = true;
    try {
      final page = await _service.fetchFeed(mode: _mode, cursor: _cursor, limit: 12);
      if (!mounted) return;
      // Duplicate guard: a shifting ranking score can otherwise repeat a reel
      // across page boundaries.
      final fresh = page.reels.where((r) => _seenIds.add(r.id)).toList();
      setState(() {
        _reels.addAll(fresh);
        _cursor = page.nextCursor;
      });
      await _ensureMediaAround(_index);
    } catch (_) {
      // A failed page must not break the reels already on screen.
    } finally {
      _loadingMore = false;
    }
  }

  /// Signs the window the viewer can reach next, in one call.
  Future<void> _ensureMediaAround(int index) async {
    if (_reels.isEmpty) return;
    final ids = <String>[];
    for (var offset = -1; offset <= 3; offset++) {
      final i = index + offset;
      if (i >= 0 && i < _reels.length) ids.add(_reels[i].id);
    }
    await _service.ensureMedia(ids);
    if (mounted) setState(() {});
  }

  void _onPageChanged(int index) {
    final previous = _index;
    if (previous < _reels.length) {
      ReelAnalytics.skip(_reels[previous], watched: _watchedFor(_reels[previous]));
    }
    setState(() => _index = index);
    _recordImpression(index);
    unawaited(_ensureMediaAround(index));
    if (index >= _reels.length - 4) unawaited(_loadMore());
  }

  Duration _watchedFor(Reel reel) {
    final start = _impressionAt[reel.id];
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  void _recordImpression(int index) {
    if (index < 0 || index >= _reels.length) return;
    final reel = _reels[index];
    _impressionAt[reel.id] = DateTime.now();
    _quartilesFired.removeWhere((key) => key.startsWith('${reel.id}:'));
    ReelAnalytics.impression(reel, position: index, feedMode: _mode);
  }

  void _onProgress(Reel reel, Duration position, Duration duration) {
    if (duration <= Duration.zero) return;
    final fraction = position.inMilliseconds / duration.inMilliseconds;
    void fireOnce(String label, double threshold) {
      if (fraction < threshold) return;
      final key = '${reel.id}:$label';
      // Each threshold fires once per playback, so a loop or a scrub back
      // does not inflate the numbers.
      if (!_quartilesFired.add(key)) return;
      ReelAnalytics.progress(reel, label, position: position);
    }

    if (position >= const Duration(seconds: 3)) fireOnce('3s', 0);
    fireOnce('25', 0.25);
    fireOnce('50', 0.5);
    fireOnce('75', 0.75);
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reel_grace_muted', _muted);
  }

  Future<void> _switchMode(String mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('reel-grace-screen'),
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0.5;
        if (visible == _visible) return;
        _visible = visible;
        if (!visible) {
          MediaPlaybackCoordinator.instance.stopAll();
        }
        if (mounted) setState(() {});
      },
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              if (_loading)
                const Center(child: CircularProgressIndicator(color: Colors.white70))
              else if (_error != null)
                _ReelMessage(
                  icon: Icons.error_outline,
                  message: 'Reels could not load right now.',
                  actionLabel: 'Try again',
                  onAction: () => _load(refresh: true),
                )
              else if (_reels.isEmpty)
                _ReelMessage(
                  icon: Icons.videocam_off_outlined,
                  message: _mode == 'following'
                      ? 'Reels from people you follow will appear here.'
                      : 'No reels yet. Be the first to share one.',
                  actionLabel: 'Refresh',
                  onAction: () => _load(refresh: true),
                )
              else
                PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _reels.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    final reel = _reels[index];
                    final isCurrent =
                        index == _index && widget.isActive && _visible;
                    final distance = (index - _index).abs();
                    // Current always; next only when Data Saver is off.
                    final shouldInitialize = widget.isActive &&
                        (distance == 0 || (!_dataSaver && index == _index + 1));
                    return _ReelPage(
                      reel: reel,
                      service: _service,
                      isCurrent: isCurrent,
                      shouldInitialize: shouldInitialize,
                      muted: _muted,
                      onProgress: (p, d) => _onProgress(reel, p, d),
                      onCompleted: () => ReelAnalytics.complete(reel),
                      onToggleMute: _toggleMute,
                    );
                  },
                ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: _ModeSelector(
                  mode: _mode,
                  onChanged: _switchMode,
                  muted: _muted,
                  onToggleMute: _toggleMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  const _ReelPage({
    required this.reel,
    required this.service,
    required this.isCurrent,
    required this.shouldInitialize,
    required this.muted,
    required this.onProgress,
    required this.onCompleted,
    required this.onToggleMute,
  });

  final Reel reel;
  final ReelService service;
  final bool isCurrent;
  final bool shouldInitialize;
  final bool muted;
  final void Function(Duration, Duration) onProgress;
  final VoidCallback onCompleted;
  final VoidCallback onToggleMute;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ReelGracePlayer(
          reel: widget.reel,
          service: widget.service,
          isCurrent: widget.isCurrent,
          shouldInitialize: widget.shouldInitialize,
          muted: widget.muted,
          onPlaybackProgress: widget.onProgress,
          onCompleted: widget.onCompleted,
        ),
        Positioned(
          left: 16,
          right: 90,
          bottom: 28,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.reel.authorName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                ),
              ),
              if (widget.reel.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.reel.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(widget.reel.audioLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          right: 10,
          bottom: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: widget.onToggleMute,
                icon: Icon(
                  widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.onChanged,
    required this.muted,
    required this.onToggleMute,
  });

  final String mode;
  final ValueChanged<String> onChanged;
  final bool muted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    Widget tab(String value, String label) {
      final selected = mode == value;
      return TextButton(
        onPressed: () => onChanged(value),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [tab('following', 'Following'), tab('discover', 'Discover')],
    );
  }
}

class _ReelMessage extends StatelessWidget {
  const _ReelMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.white54),
            const SizedBox(height: 14),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
