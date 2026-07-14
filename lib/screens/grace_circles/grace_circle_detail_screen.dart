import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community_feed_mode.dart';
import '../../models/post.dart';
import '../../providers/user_role_provider.dart';
import '../../services/community_service.dart';
import '../../services/grace_circles_service.dart';
import '../../widgets/ui/app_scaffold.dart';

class GraceCircleDetailScreen extends StatefulWidget {
  const GraceCircleDetailScreen({
    super.key,
    required this.circleId,
  });

  final String circleId;

  @override
  State<GraceCircleDetailScreen> createState() =>
      _GraceCircleDetailScreenState();
}

class _GraceCircleDetailScreenState extends State<GraceCircleDetailScreen> {
  final GraceCirclesService _circlesService = GraceCirclesService();
  final CommunityService _communityService = CommunityService();
  final TextEditingController _postController = TextEditingController();
  late Future<GraceCircle?> _circleFuture;
  int _refreshToken = 0;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _circleFuture = _circlesService.fetchCircle(widget.circleId);
    _circlesService.joinCircle(widget.circleId);
  }

  @override
  void dispose() {
    _postController.dispose();
    super.dispose();
  }

  Future<void> _postToCircle() async {
    if (_posting) return;
    final body = _postController.text.trim();
    if (body.isEmpty) return;

    setState(() => _posting = true);
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      final profile = context.read<UserRoleProvider>().userProfile;
      if (authUser == null) return;

      await _communityService.addPost(
        Post(
          id: '',
          authorName: profile?.fullName.trim().isNotEmpty == true
              ? profile!.fullName.trim()
              : 'Grace Connect Member',
          authorId: authUser.id,
          authorPhoto: profile?.photoUrl,
          content: body,
          timestamp: DateTime.now(),
          likes: const [],
          placeId: profile?.placeId ?? '',
          originChurchId: profile?.placeId,
          circleId: widget.circleId,
          scope: 'circle',
          postType: 'circle_post',
          expiresAt: null,
          visibleToAllChurches: false,
        ),
      );
      _postController.clear();
      if (mounted) setState(() => _refreshToken++);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post to circle: $error')),
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GraceCircle?>(
      future: _circleFuture,
      builder: (context, circleSnapshot) {
        final circle = circleSnapshot.data;
        return AppScaffold(
          title: circle?.name ?? 'Grace Circle',
          body: Column(
            children: [
              if (circle != null)
                _CircleHeader(circle: circle)
              else if (circleSnapshot.connectionState ==
                  ConnectionState.waiting)
                const LinearProgressIndicator(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _postController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Share with this circle',
                          prefixIcon: Icon(Icons.edit_note_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Post',
                      onPressed: _posting ? null : _postToCircle,
                      icon: _posting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<Post>>(
                  key: ValueKey('circle-${widget.circleId}-$_refreshToken'),
                  stream: _communityService.getCommunityFeed(
                    mode: CommunityFeedMode.circle,
                    circleId: widget.circleId,
                  ),
                  builder: (context, snapshot) {
                    final posts = snapshot.data ?? const [];
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        posts.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (posts.isEmpty) {
                      return const Center(
                        child: Text('No circle posts yet.'),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                post.authorPhoto?.isNotEmpty == true
                                    ? NetworkImage(post.authorPhoto!)
                                    : null,
                            child: post.authorPhoto?.isNotEmpty == true
                                ? null
                                : const Icon(Icons.person_outline),
                          ),
                          title: Text(post.authorName),
                          subtitle: Text(post.content),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CircleHeader extends StatelessWidget {
  const _CircleHeader({required this.circle});

  final GraceCircle circle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            circle.description.trim().isEmpty
                ? 'A shared Grace Connect circle.'
                : circle.description.trim(),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.people_outline, size: 16),
              const SizedBox(width: 6),
              Text('${circle.memberCount} members'),
            ],
          ),
        ],
      ),
    );
  }
}
