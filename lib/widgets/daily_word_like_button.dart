import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/daily_grace_service.dart';
import '../services/daily_word_likes_service.dart';
import '../services/haptic_service.dart';
import '../utils/compact_count.dart';

class DailyWordLikeButton extends StatefulWidget {
  const DailyWordLikeButton(
      {super.key,
      required this.motivationId,
      this.likeOnOpen = false,
      this.service});
  final String motivationId;
  final bool likeOnOpen;
  final DailyWordLikesService? service;

  @override
  State<DailyWordLikeButton> createState() => _DailyWordLikeButtonState();
}

class _DailyWordLikeButtonState extends State<DailyWordLikeButton>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? DailyWordLikesService();
  DailyWordEngagement? _value;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A widget heart explicitly requests a like, never a toggle. Re-opening
    // the same pending intent cannot accidentally remove the person's like.
    unawaited(widget.likeOnOpen ? _setLiked(true) : _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) unawaited(_load());
  }

  void _publish(DailyWordEngagement value) {
    if (!mounted) return;
    setState(() {
      _value = value;
      _failed = false;
    });
    unawaited(DailyGraceService.syncQuoteEngagement(
        widget.motivationId, value.count, value.liked));
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _publish(await _service.fetch(widget.motivationId));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLiked(bool liked) async {
    if (_busy) return;
    final previous = _value;
    setState(() {
      _busy = true;
      if (previous != null) {
        _value = DailyWordEngagement(
            count: previous.count +
                (previous.liked == liked
                    ? 0
                    : liked
                        ? 1
                        : -1),
            liked: liked);
      }
    });
    try {
      _publish(await _service.setLiked(widget.motivationId, liked));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _value = previous;
        _failed = previous == null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your like could not be updated. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final exact = value == null
        ? 'Likes'
        : '${NumberFormat.decimalPattern().format(value.count)} likes';
    return Tooltip(
      message: exact,
      child: Semantics(
        label:
            '$exact. ${value?.liked == true ? 'Liked' : 'Like this Daily Word'}',
        toggled: value?.liked == true,
        child: OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  HapticService.light();
                  if (value == null) {
                    unawaited(_load());
                  } else {
                    unawaited(_setLiked(!value.liked));
                  }
                },
          icon: Icon(
              value?.liked == true ? Icons.favorite : Icons.favorite_border,
              color: value?.liked == true
                  ? Theme.of(context).colorScheme.primary
                  : null),
          label: Text(value == null
              ? (_failed ? 'Retry likes' : 'Loading likes…')
              : '${value.liked ? 'Liked' : 'Like'} · ${compactCount(value.count)}'),
        ),
      ),
    );
  }
}
