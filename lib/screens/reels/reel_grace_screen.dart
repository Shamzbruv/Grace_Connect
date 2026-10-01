import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../models/reel.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/reel_analytics_service.dart';
import '../../services/moderation_service.dart';
import '../../services/reel_service.dart';
import '../../services/reel_playback_window.dart';
import '../../widgets/reels/reel_action_rail.dart';
import '../../widgets/reels/reel_comments_sheet.dart';
import '../../widgets/reels/reel_grace_player.dart';
import '../../widgets/reels/reel_mode_header.dart';
import 'reel_create_screen.dart';
import '../../widgets/share/content_share_sheet.dart';

/// Full-screen vertical reel feed.
///
/// Controller budget: the current reel, plus the next one so a swipe starts
/// instantly. Everything else is poster-only. Under Data Saver only the
/// current reel initializes at all, so nothing speculative is downloaded.
class ReelGraceScreen extends StatefulWidget {
  const ReelGraceScreen({super.key, required this.isActive, this.reelId});

  /// Whether Reel Grace is the visible mode. When false, playback stops --
  /// the widget stays alive so the feed position survives a mode switch.
  final bool isActive;
  final String? reelId;

  @override
  State<ReelGraceScreen> createState() => _ReelGraceScreenState();
}

class _ReelGraceScreenState extends State<ReelGraceScreen>
    with WidgetsBindingObserver {
  final ReelService _service = ReelService();
  final PageController _pageController = PageController(keepPage: false);
  final List<Reel> _reels = [];
  final Set<String> _seenIds = {};
  final Map<String, DateTime> _impressionAt = {};
  final Set<String> _quartilesFired = {};

  Map<String, dynamic>? _cursor;
  String _mode = 'discover';
  int _index = 0;
  int? _warmPreviousIndex;
  Timer? _warmPreviousTimer;
  bool _loading = true;
  bool _loadingMore = false;
  bool _muted = false;
  bool _dataSaver = false;
  bool _visible = false;
  bool _foreground = true;
  bool _overlayOpen = false;
  bool _autoScroll = false;
  final Set<String> _likeWrites = {};
  final Set<String> _saveWrites = {};
  String? _error;
  int _loadGeneration = 0;

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
    _warmPreviousTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) {
      // Backgrounding must silence playback immediately, not on the next
      // frame after the app is already gone from view.
      MediaPlaybackCoordinator.instance.stopAll();
      if (mounted) setState(() {});
    }
    if (_foreground && mounted) setState(() {});
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
      // Each visit starts with sound. Muting remains available during viewing.
    });
  }

  Future<void> _load({bool refresh = false}) async {
    final generation = ++_loadGeneration;
    _cursor = null;
    _loadingMore = false;
    _warmPreviousTimer?.cancel();
    _warmPreviousIndex = null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ReelPage page;
      if (widget.reelId != null) {
        final reel = await _service.fetchDetail(widget.reelId!);
        page = ReelPage(reels: reel == null ? [] : [reel]);
      } else {
        page = await _service.fetchFeed(mode: _mode, limit: 12);
      }
      if (!mounted || generation != _loadGeneration) return;
      _seenIds.clear();
      final fresh = page.reels.where((r) => _seenIds.add(r.id)).toList();
      setState(() {
        _reels
          ..clear()
          ..addAll(fresh);
        _cursor = page.nextCursor;
        _loading = false;
        _index = 0;
      });
      _recordImpression(0);
      await _ensureMediaAround(0);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _cursor == null) return;
    final generation = _loadGeneration;
    _loadingMore = true;
    try {
      final page =
          await _service.fetchFeed(mode: _mode, cursor: _cursor, limit: 12);
      if (!mounted || generation != _loadGeneration) return;
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
      if (generation == _loadGeneration) _loadingMore = false;
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
    _warmPreviousTimer?.cancel();
    _warmPreviousIndex = previous == index - 1 ? previous : null;
    _warmPreviousTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _warmPreviousIndex = null);
    });
    if (previous < _reels.length) {
      ReelAnalytics.skip(_reels[previous],
          watched: _watchedFor(_reels[previous]));
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

  /// Optimistic: the heart moves now and rolls back only if the write is
  /// refused. Waiting on the network to animate a like is the difference
  /// between the feed feeling native and feeling remote.
  Future<void> _toggleLike(Reel reel) async {
    if (!_likeWrites.add(reel.id)) return;
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index < 0) {
      _likeWrites.remove(reel.id);
      return;
    }
    final liked = !reel.viewerLiked;
    setState(() => _reels[index] = reel.copyWith(
          viewerLiked: liked,
          likeCount: (reel.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        ));
    ReelAnalytics.like(reel, liked: liked);
    final ok = await _service.toggleLike(reel.id, liked: liked);
    _likeWrites.remove(reel.id);
    if (!ok && mounted) {
      final current = _reels.indexWhere((r) => r.id == reel.id);
      if (current >= 0) {
        setState(() => _reels[current] = _reels[current].copyWith(
            viewerLiked: reel.viewerLiked, likeCount: reel.likeCount));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not update your like. Please try again.')));
    }
  }

  Future<void> _toggleSave(Reel reel) async {
    if (!_saveWrites.add(reel.id)) return;
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index < 0) {
      _saveWrites.remove(reel.id);
      return;
    }
    final saved = !reel.viewerSaved;
    setState(() => _reels[index] = reel.copyWith(
          viewerSaved: saved,
          saveCount: (reel.saveCount + (saved ? 1 : -1)).clamp(0, 1 << 30),
        ));
    ReelAnalytics.save(reel, saved: saved);
    final ok = await _service.toggleSave(reel.id, saved: saved);
    _saveWrites.remove(reel.id);
    if (!ok && mounted) {
      final current = _reels.indexWhere((r) => r.id == reel.id);
      if (current >= 0) {
        setState(() => _reels[current] = _reels[current].copyWith(
            viewerSaved: reel.viewerSaved, saveCount: reel.saveCount));
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not update your saved reels. Please try again.')));
    }
  }

  Future<void> _share(Reel reel) async {
    ReelAnalytics.share(reel);
    setState(() => _overlayOpen = true);
    await showContentShareSheet(context, reel: reel);
    if (mounted) setState(() => _overlayOpen = false);
  }

  void _removeFromFeed(String reelId) {
    final index = _reels.indexWhere((r) => r.id == reelId);
    if (index < 0) return;
    setState(() {
      _reels.removeAt(index);
      _service.forget(reelId);
      if (_index >= _reels.length) {
        _index = (_reels.length - 1).clamp(0, 1 << 30);
      }
    });
  }

  Future<void> _notInterested(Reel reel) async {
    // Removed from view straight away; the server call only needs to make it
    // stick for future pages.
    _removeFromFeed(reel.id);
    await _service.markNotInterested(reel.id);
  }

  Future<void> _report(Reel reel) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Report this reel',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            for (final reason in const [
              'Inappropriate content',
              'Harassment or bullying',
              'False teaching',
              'Spam or misleading',
              'Something else',
            ])
              ListTile(
                title: Text(reason),
                onTap: () => Navigator.of(context).pop(reason),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    await ModerationService().reportContent(
      // A reel belongs to no single church, so this reports into the global
      // scope rather than silently doing nothing for a church-less viewer.
      churchId: reel.authorChurchId ?? '',
      contentType: 'reel',
      contentId: reel.id,
      reportedUserId: reel.authorId,
      reason: reason,
    );
    if (!mounted) return;
    _removeFromFeed(reel.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thank you. Our team will review this.')),
    );
  }

  Future<void> _blockCreator(Reel reel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${reel.authorName}?'),
        content: const Text(
            'You will stop seeing their reels and posts, and they will not see yours.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Block')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ModerationService().blockUser(
      churchId: reel.authorChurchId ?? '',
      blockedUserId: reel.authorId,
    );
    if (!mounted) return;
    setState(() {
      _reels.removeWhere((r) => r.authorId == reel.authorId);
      if (_index >= _reels.length) {
        _index = (_reels.length - 1).clamp(0, 1 << 30);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${reel.authorName} is blocked.')),
    );
  }

  Future<void> _openProfile(Reel reel) async {
    ReelAnalytics.profileOpen(reel);
    setState(() => _overlayOpen = true);
    await Navigator.of(context)
        .pushNamed('/public_profile', arguments: reel.authorId);
    if (mounted) setState(() => _overlayOpen = false);
  }

  Future<void> _showMore(Reel reel) async {
    setState(() => _overlayOpen = true);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading:
                  Icon(_autoScroll ? Icons.swipe_up : Icons.swipe_up_outlined),
              title: Text(
                  _autoScroll ? 'Turn off auto-scroll' : 'Turn on auto-scroll'),
              subtitle:
                  const Text('Move to the next reel when this one finishes'),
              onTap: () => Navigator.pop(context, 'auto_scroll'),
            ),
            ListTile(
              leading: const Icon(Icons.not_interested),
              title: const Text('Not interested'),
              subtitle: const Text('Show me fewer reels like this'),
              onTap: () => Navigator.pop(context, 'not_interested'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () => Navigator.pop(context, 'report'),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text('Block ${reel.authorName}'),
              onTap: () => Navigator.pop(context, 'block'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      switch (choice) {
        case 'auto_scroll':
          setState(() => _autoScroll = !_autoScroll);
        case 'not_interested':
          await _notInterested(reel);
        case 'report':
          await _report(reel);
        case 'block':
          await _blockCreator(reel);
      }
    } finally {
      if (mounted) setState(() => _overlayOpen = false);
    }
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
  }

  Future<void> _onCompleted(Reel reel) async {
    ReelAnalytics.complete(reel);
    if (!_autoScroll ||
        !_foreground ||
        _overlayOpen ||
        !widget.isActive ||
        !_visible) {
      return;
    }
    final completedId = reel.id;
    if (_index >= _reels.length - 1) await _loadMore();
    if (!mounted ||
        !_autoScroll ||
        !_foreground ||
        _overlayOpen ||
        !widget.isActive ||
        !_visible ||
        !_pageController.hasClients ||
        _index >= _reels.length - 1 ||
        _reels[_index].id != completedId) {
      return;
    }
    await _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _switchMode(String mode) async {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ObjectKey(this),
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
                const Center(
                    child: CircularProgressIndicator(color: Colors.white70))
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
                    final isCurrent = index == _index &&
                        widget.isActive &&
                        _visible &&
                        _foreground &&
                        !_overlayOpen;
                    // Current always; next only when Data Saver is off.
                    final shouldInitialize = shouldInitializeReel(
                        index: index,
                        current: _index,
                        dataSaver: _dataSaver,
                        isActive: widget.isActive && _foreground,
                        warmPreviousIndex: _warmPreviousIndex);
                    return _ReelPage(
                      key: ValueKey(reel.id),
                      reel: reel,
                      service: _service,
                      isCurrent: isCurrent,
                      shouldInitialize: shouldInitialize,
                      muted: _muted,
                      onProgress: (p, d) => _onProgress(reel, p, d),
                      onCompleted: () => _onCompleted(reel),
                      onToggleMute: _toggleMute,
                      onLike: () => _toggleLike(reel),
                      onComment: () async {
                        setState(() => _overlayOpen = true);
                        ReelAnalytics.commentOpen(reel);
                        await showReelComments(context, reel);
                        if (mounted) setState(() => _overlayOpen = false);
                        try {
                          final latest = await _service.fetchDetail(reel.id);
                          if (!mounted || latest == null) return;
                          final current =
                              _reels.indexWhere((r) => r.id == reel.id);
                          if (current >= 0) {
                            setState(() => _reels[current] = _reels[current]
                                .copyWith(commentCount: latest.commentCount));
                          }
                        } catch (_) {
                          /* Counts refresh on the next feed request. */
                        }
                      },
                      onSave: () => _toggleSave(reel),
                      onShare: () => _share(reel),
                      onProfile: () => _openProfile(reel),
                      onMore: () => _showMore(reel),
                    );
                  },
                ),
              if (widget.reelId == null)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: ReelModeHeader(
                    mode: _mode,
                    onModeChanged: _switchMode,
                    onCreate: () async {
                      setState(() => _overlayOpen = true);
                      final posted = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const ReelCreateScreen()),
                      );
                      if (!mounted) return;
                      setState(() => _overlayOpen = false);
                      if (posted == true) await _load(refresh: true);
                    },
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
    super.key,
    required this.reel,
    required this.service,
    required this.isCurrent,
    required this.shouldInitialize,
    required this.muted,
    required this.onProgress,
    required this.onCompleted,
    required this.onToggleMute,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.onShare,
    required this.onProfile,
    required this.onMore,
  });

  final Reel reel;
  final ReelService service;
  final bool isCurrent;
  final bool shouldInitialize;
  final bool muted;
  final void Function(Duration, Duration) onProgress;
  final VoidCallback onCompleted;
  final VoidCallback onToggleMute;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onProfile;
  final VoidCallback onMore;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.shouldInitialize;

  @override
  void didUpdateWidget(covariant _ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shouldInitialize != widget.shouldInitialize) {
      updateKeepAlive();
    }
  }

  bool _captionExpanded = false;
  late final AnimationController _heart = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    // Double tap always likes, never unlikes -- an accidental second
    // double-tap should not quietly undo the like the member just gave.
    if (!widget.reel.viewerLiked) widget.onLike();
    _heart.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final reel = widget.reel;
    final caption = reel.caption.trim();
    final isLong = caption.length > 90;

    return Stack(
      fit: StackFit.expand,
      children: [
        ReelGracePlayer(
          reel: reel,
          service: widget.service,
          isCurrent: widget.isCurrent,
          shouldInitialize: widget.shouldInitialize,
          muted: widget.muted,
          onPlaybackProgress: widget.onProgress,
          onCompleted: widget.onCompleted,
          onDoubleTap: _onDoubleTap,
          onLongPress: widget.onMore,
        ),
        // Scrim so white text stays legible over a bright video.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 260,
          child: IgnorePointer(
              child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
          )),
        ),
        IgnorePointer(
          child: Center(
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.6, end: 1.25).animate(
                CurvedAnimation(parent: _heart, curve: Curves.easeOutBack),
              ),
              child: FadeTransition(
                opacity: Tween<double>(begin: 1, end: 0).animate(
                  CurvedAnimation(
                      parent: _heart, curve: const Interval(0.5, 1)),
                ),
                child:
                    const Icon(Icons.favorite, color: Colors.white, size: 96),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 92,
          bottom: 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: widget.onProfile,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        reel.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6)
                          ],
                        ),
                      ),
                    ),
                    if (reel.visibility != ReelVisibility.public) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          reel.visibility.label,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: isLong
                      ? () =>
                          setState(() => _captionExpanded = !_captionExpanded)
                      : null,
                  child: RichText(
                    maxLines: _captionExpanded ? 8 : 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                      children: [
                        TextSpan(text: caption),
                        if (isLong && !_captionExpanded)
                          const TextSpan(
                            text: '  more',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      reel.audioLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: widget.onToggleMute,
                    child: Icon(
                      widget.muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          bottom: 26,
          child: ReelActionRail(
            reel: reel,
            onLike: widget.onLike,
            onComment: widget.onComment,
            onSave: widget.onSave,
            onShare: widget.onShare,
            onProfile: widget.onProfile,
            onMore: widget.onMore,
          ),
        ),
      ],
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
