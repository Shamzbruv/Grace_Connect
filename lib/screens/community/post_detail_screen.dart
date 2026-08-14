import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/post.dart';
import '../../services/community_service.dart';
import '../../utils/media_display_format.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../widgets/community_video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final CommunityService _communityService = CommunityService();
  final TextEditingController _commentController = TextEditingController();
  final GoTrueClient _auth = Supabase.instance.client.auth;
  bool _isPosting = false;
  int _commentsRefreshToken = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handlePostComment() async {
    if (_isPosting) return;
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isPosting = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      String authorName = user.userMetadata?['full_name'] ?? 'Anonymous';

      await _communityService.addComment(widget.post.id, {
        'content': content,
        'author_id': user.id,
        'author_name': authorName,
        'author_photo': user.userMetadata?['avatar_url'],
      });

      _commentController.clear();
      if (mounted) {
        setState(() => _commentsRefreshToken++);
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _confirmDeletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
            'This will remove your post, its comments, and any attached media.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _communityService.deletePost(widget.post);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete post: $e')),
      );
    }
  }

  Future<void> _confirmDeleteComment(Map<String, dynamic> comment) async {
    final commentId = comment['id'] as String?;
    if (commentId == null || commentId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This will remove your comment from the post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _communityService.deleteComment(commentId);
      if (!mounted) return;
      setState(() => _commentsRefreshToken++);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment deleted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete comment: $e')),
      );
    }
  }

  void _openPostMediaViewer(Post post) {
    final mediaUrl = post.mediaUrl?.trim();
    if (mediaUrl == null || mediaUrl.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PostMediaViewerScreen(
          mediaUrl: mediaUrl,
          mediaType: post.mediaType ?? 'image',
          mediaThumbnailUrl: post.mediaThumbnailUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Post Details',
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main Post
                  StreamBuilder<Post?>(
                    stream: _communityService.getPost(widget.post.id),
                    builder: (context, snapshot) {
                      final post = snapshot.data ?? widget.post;
                      final canDeletePost =
                          post.authorId == _auth.currentUser?.id;

                      return Container(
                        color: Theme.of(context).cardTheme.color,
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundImage: post.authorPhoto != null
                                      ? NetworkImage(post.authorPhoto!)
                                      : null,
                                  child: post.authorPhoto == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        post.authorName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        timeago.format(post.timestamp),
                                        style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (canDeletePost)
                                  PopupMenuButton<String>(
                                    tooltip: 'Post options',
                                    icon: const Icon(Icons.more_horiz),
                                    onSelected: (value) {
                                      if (value == 'delete') {
                                        _confirmDeletePost();
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (post.content.isNotEmpty)
                              Text(post.content,
                                  style: const TextStyle(fontSize: 16)),

                            if (post.mediaUrl != null &&
                                post.mediaType == 'image') ...[
                              const SizedBox(height: 16),
                              AspectRatio(
                                aspectRatio: safeMediaAspectRatio(
                                  post.mediaAspectRatio,
                                  fallback: 4 / 3,
                                ),
                                child: GestureDetector(
                                  onTap: () => _openPostMediaViewer(post),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ColoredBox(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: CachedNetworkImage(
                                        imageUrl: post.mediaUrl!,
                                        placeholder: (context, url) =>
                                            const Center(
                                                child: Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: CircularProgressIndicator(),
                                        )),
                                        errorWidget: (context, url, error) =>
                                            const Icon(Icons.error),
                                        fit: boxFitForMedia(post.mediaFit),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (post.mediaUrl != null &&
                                post.mediaType == 'video') ...[
                              const SizedBox(height: 16),
                              AspectRatio(
                                aspectRatio: safeMediaAspectRatio(
                                  post.mediaAspectRatio,
                                  fallback: 4 / 3,
                                ),
                                child: GestureDetector(
                                  onTap: () => _openPostMediaViewer(post),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CommunityVideoPlayer(
                                      mediaUrl: post.mediaUrl!,
                                      thumbnailUrl: post.mediaThumbnailUrl,
                                      fit: boxFitForMedia(post.mediaFit),
                                    ),
                                  ),
                                ),
                              )
                            ],
                            const SizedBox(height: 16),
                            const Divider(),
                            // Stats
                            Row(
                              children: [
                                Icon(Icons.favorite,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${post.likes.length} Likes',
                                    style: TextStyle(color: Colors.grey[600])),
                                const SizedBox(width: 16),
                                Icon(Icons.comment,
                                    size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text('${post.commentsCount} Comments',
                                    style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // Comments List
                  StreamBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey(_commentsRefreshToken),
                    stream: _communityService.getComments(widget.post.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Error: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()));
                      }

                      final comments = _dedupeComments(snapshot.data ?? []);
                      if (comments.isEmpty) {
                        return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No comments yet.')));
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final data = comments[index];
                          final timeStr = data['created_at'] as String?;
                          final time = timeStr != null
                              ? DateTime.parse(timeStr).toLocal()
                              : null;
                          final canDeleteComment =
                              data['author_id'] == _auth.currentUser?.id;

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundImage: data['author_photo'] != null
                                  ? NetworkImage(data['author_photo'])
                                  : null,
                              child: data['author_photo'] == null
                                  ? const Icon(Icons.person, size: 16)
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Text(data['author_name'] ?? 'Anonymous',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                const SizedBox(width: 8),
                                Text(
                                  time != null
                                      ? timeago.format(time, locale: 'en_short')
                                      : '',
                                  style: TextStyle(
                                      color: Colors.grey[500], fontSize: 12),
                                ),
                              ],
                            ),
                            subtitle: Text(data['content'] ?? ''),
                            trailing: canDeleteComment
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: 'Delete comment',
                                    onPressed: () =>
                                        _confirmDeleteComment(data),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Comment Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _commentController,
                    hint: 'Write a comment...',
                    suffixIcon: _isPosting
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(
                            icon: Icon(Icons.send,
                                color: Theme.of(context).colorScheme.primary),
                            onPressed: _handlePostComment,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _dedupeComments(
      List<Map<String, dynamic>> comments) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final comment in comments) {
      final id = comment['id']?.toString();
      final fallbackKey = [
        comment['post_id'],
        comment['author_id'],
        comment['content'],
        comment['created_at'],
      ].join('|');
      final key = id == null || id.isEmpty ? fallbackKey : id;
      if (seen.add(key)) unique.add(comment);
    }
    return unique;
  }
}

class _PostMediaViewerScreen extends StatelessWidget {
  const _PostMediaViewerScreen({
    required this.mediaUrl,
    required this.mediaType,
    this.mediaThumbnailUrl,
  });

  final String mediaUrl;
  final String mediaType;
  final String? mediaThumbnailUrl;

  @override
  Widget build(BuildContext context) {
    final isVideo = mediaType == 'video';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(isVideo ? 'Video' : 'Photo'),
      ),
      body: SafeArea(
        child: Center(
          child: isVideo
              ? SizedBox.expand(
                  child: CommunityVideoPlayer(
                    mediaUrl: mediaUrl,
                    thumbnailUrl: mediaThumbnailUrl,
                    fit: BoxFit.contain,
                  ),
                )
              : InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: CachedNetworkImage(
                    imageUrl: mediaUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
