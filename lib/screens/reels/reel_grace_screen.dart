import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../models/reel.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/reel_analytics_service.dart';
import '../../services/moderation_service.dart';
import '../../services/reel_service.dart';
import '../../widgets/reels/reel_action_rail.dart';
import '../../widgets/reels/reel_comments_sheet.dart';
import '../../widgets/reels/reel_grace_player.dart';
import 'reel_create_screen.dart';
import 'package:share_plus/share_plus.dart';

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

  /// Optimistic: the heart moves now and rolls back only if the write is
  /// refused. Waiting on the network to animate a like is the difference
  /// between the feed feeling native and feeling remote.
  Future<void> _toggleLike(Reel reel) async {
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index < 0) return;
    final liked = !reel.viewerLiked;
    setState(() => _reels[index] = reel.copyWith(
          viewerLiked: liked,
          likeCount: (reel.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
        ));
    ReelAnalytics.like(reel, liked: liked);
    final ok = await _service.toggleLike(reel.id, liked: liked);
    if (!ok && mounted) {
      setState(() => _reels[index] = reel);
    }
  }

  Future<void> _toggleSave(Reel reel) async {
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index < 0) return;
    final saved = !reel.viewerSaved;
    setState(() => _reels[index] = reel.copyWith(
          viewerSaved: saved,
          saveCount: (reel.saveCount + (saved ? 1 : -1)).clamp(0, 1 << 30),
        ));
    ReelAnalytics.save(reel, saved: saved);
    final ok = await _service.toggleSave(reel.id, saved: saved);
    if (!ok && mounted) setState(() => _reels[index] = reel);
  }

  Future<void> _share(Reel reel) async {
    ReelAnalytics.share(reel);
    final caption = reel.caption.trim();
    await SharePlus.instance.share(ShareParams(
      text: caption.isEmpty
          ? 'Watch this on Grace Connect.'
          : '$caption\n\nShared from Grace Connect.',
      subject: 'A reel from ${reel.authorName}',
    ));
  }

  void _removeFromFeed(String reelId) {
    final index = _reels.indexWhere((r) => r.id == reelId);
    if (index < 0) return;
    setState(() {
      _reels.removeAt(index);
      _service.forget(reelId);
      if (_index >= _reels.length) _index = (_reels.length - 1).clamp(0, 1 << 30);
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
      if (_index >= _reels.length) _index = (_reels.length - 1).clamp(0, 1 << 30);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${reel.authorName} is blocked.')),
    );
  }

  void _openProfile(Reel reel) {
    ReelAnalytics.profileOpen(reel);
    Navigator.of(context).pushNamed('/public_profile', arguments: reel.authorId);
  }

  Future<void> _showMore(Reel reel) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'not_interested':
        await _notInterested(reel);
      case 'report':
        await _report(reel);
      case 'block':
        await _blockCreator(reel);
    }
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
                      onLike: () => _toggleLike(reel),
                      onComment: () {
                        ReelAnalytics.commentOpen(reel);
                        showReelComments(context, reel);
                      },
                      onSave: () => _toggleSave(reel),
                      onShare: () => _share(reel),
                      onProfile: () => _openProfile(reel),
                      onMore: () => _showMore(reel),
                    );
                  },
                ),
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeSelector(
                        mode: _mode,
                        onChanged: _switchMode,
                        muted: _muted,
                        onToggleMute: _toggleMute,
                      ),
                    ),
                    IconButton(
                      tooltip: 'New reel',
                      onPressed: () async {
                        final posted = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                              builder: (_) => const ReelCreateScreen()),
                        );
                        if (posted == true) await _load(refresh: true);
                      },
                      icon: const Icon(Icons.add_box_outlined,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                  ],
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
    with SingleTickerProviderStateMixin {
  bool _captionExpanded = false;
  late final AnimationController _heart = AnimationController(
    vsync: this,
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
    final reel = widget.reel;
    final caption = reel.caption.trim();
    final isLong = caption.length > 90;

    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Stack(
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
          ),
          // Scrim so white text stays legible over a bright video.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 260,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1.25).animate(
                  CurvedAnimation(parent: _heart, curve: Curves.easeOutBack),
                ),
                child: FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(
                    CurvedAnimation(parent: _heart, curve: const Interval(0.5, 1)),
                  ),
                  child: const Icon(Icons.favorite,
                      color: Colors.white, size: 96),
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
                            shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
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
                        ? () => setState(() => _captionExpanded = !_captionExpanded)
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
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
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
      ),
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
