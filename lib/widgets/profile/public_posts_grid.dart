import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/post.dart';
import '../../services/haptic_service.dart';

/// A profile's posts as a square grid, the way people expect a profile to
/// look.
///
/// A vertical list of cards reads as a feed, not as a body of work: it shows
/// three or four posts per screen and buries each image behind its text. The
/// grid shows a dozen at a glance and puts the picture first.
///
/// Shared by the member and church profiles so the two do not drift apart.
class PublicPostsGrid extends StatelessWidget {
  const PublicPostsGrid({
    super.key,
    required this.posts,
    this.emptyState,
  });

  final List<Post> posts;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return emptyState ?? const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        // 2px gutters, not 12: the tiles should read as one sheet of images,
        // which is what makes a grid feel like a grid rather than a list of
        // small cards.
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        childAspectRatio: 1,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) => PublicPostTile(post: posts[index]),
    );
  }
}

class PublicPostTile extends StatelessWidget {
  const PublicPostTile({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The thumbnail is preferred where one exists: a grid pulls up to a
    // dozen images at once, and full-size media would make the profile
    // expensive to open on a phone connection.
    final mediaUrl = (post.mediaThumbnailUrl?.trim().isNotEmpty ?? false)
        ? post.mediaThumbnailUrl!.trim()
        : (post.mediaType?.toLowerCase().startsWith('video') == true
            ? ''
            : (post.mediaUrl?.trim() ?? ''));
    final isVideo = (post.mediaType?.toLowerCase() ?? '').startsWith('video');

    return InkWell(
      onTap: () {
        HapticService.selection();
        Navigator.of(context).pushNamed(
          '/community_post?entityTable=community_posts'
          '&entityId=${Uri.encodeComponent(post.id)}',
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (mediaUrl.isEmpty)
            _TextOnlyTile(post: post)
          else
            CachedNetworkImage(
              imageUrl: mediaUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (context, url, error) => _TextOnlyTile(post: post),
            ),
          if (isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(
                Icons.play_circle_fill,
                size: 18,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
        ],
      ),
    );
  }
}

/// A text-only post still has to fill its square, so the words become the
/// tile rather than leaving a blank hole in the grid.
class _TextOnlyTile extends StatelessWidget {
  const _TextOnlyTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      child: Text(
        post.content.trim().isEmpty ? 'Shared a post' : post.content.trim(),
        maxLines: 5,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
