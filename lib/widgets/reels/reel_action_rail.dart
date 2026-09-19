import 'package:flutter/material.dart';

import '../../models/reel.dart';

/// The right-side action column. Grace Connect's own styling rather than a
/// copy of another app's: rounded surface-tinted buttons with the app's icon
/// set, counts underneath in the app's type scale.
class ReelActionRail extends StatelessWidget {
  const ReelActionRail({
    super.key,
    required this.reel,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    required this.onShare,
    required this.onProfile,
    required this.onMore,
  });

  final Reel reel;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onProfile;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailAvatar(reel: reel, onTap: onProfile),
        const SizedBox(height: 18),
        _RailButton(
          icon: reel.viewerLiked ? Icons.favorite : Icons.favorite_border,
          colour: reel.viewerLiked ? const Color(0xFFE5484D) : Colors.white,
          label: _count(reel.likeCount),
          onTap: onLike,
          semanticLabel: reel.viewerLiked ? 'Unlike' : 'Like',
        ),
        const SizedBox(height: 16),
        if (reel.commentsEnabled)
          _RailButton(
            icon: Icons.mode_comment_outlined,
            label: _count(reel.commentCount),
            onTap: onComment,
            semanticLabel: 'Comments',
          ),
        if (reel.commentsEnabled) const SizedBox(height: 16),
        _RailButton(
          icon: reel.viewerSaved ? Icons.bookmark : Icons.bookmark_border,
          label: _count(reel.saveCount),
          onTap: onSave,
          semanticLabel: reel.viewerSaved ? 'Remove from saved' : 'Save',
        ),
        const SizedBox(height: 16),
        _RailButton(
          icon: Icons.ios_share_outlined,
          label: 'Share',
          onTap: onShare,
          semanticLabel: 'Share this reel',
        ),
        const SizedBox(height: 16),
        _RailButton(
          icon: Icons.more_horiz,
          label: '',
          onTap: onMore,
          semanticLabel: 'More options',
        ),
      ],
    );
  }

  static String _count(int value) {
    if (value <= 0) return '';
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(value < 10000 ? 1 : 0)}K';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}

class _RailAvatar extends StatelessWidget {
  const _RailAvatar({required this.reel, required this.onTap});

  final Reel reel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatar = reel.authorAvatarUrl;
    return Semantics(
      button: true,
      label: 'Open ${reel.authorName}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Colors.black38,
            backgroundImage:
                avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
            child: avatar != null && avatar.isNotEmpty
                ? null
                : const Icon(Icons.person, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.semanticLabel,
    this.colour = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String semanticLabel;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colour, size: 24),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
