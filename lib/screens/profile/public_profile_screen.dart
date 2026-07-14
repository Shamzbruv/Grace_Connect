import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/post.dart';
import '../../models/social_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/community_service.dart';
import '../../services/social_profile_service.dart';
import '../../widgets/profile_photo_viewer.dart';
import '../../widgets/ui/app_scaffold.dart';

class PublicProfileScreen extends StatefulWidget {
  const PublicProfileScreen({
    super.key,
    this.userId,
  });

  final String? userId;

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final SocialProfileService _service = SocialProfileService();
  final CommunityService _communityService = CommunityService();
  late Future<SocialProfile?> _profileFuture;
  late Future<List<Post>> _postsFuture;
  String _followStatus = 'none';
  bool _updatingFollow = false;
  int? _followerCountOverride;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _postsFuture = Future.value(const []);
  }

  Future<SocialProfile?> _loadProfile() async {
    final userId = widget.userId?.trim().isNotEmpty == true
        ? widget.userId!.trim()
        : _service.currentUserId;
    if (userId == null) return null;
    final profile = await _service.fetchProfile(userId);
    if (profile != null && mounted) {
      setState(() {
        _postsFuture = _communityService.fetchPublicPostsByAuthor(
          profile.userId,
        );
        _followerCountOverride ??= profile.followerCount;
      });
      final status = await _service.followStatus(profile.userId);
      if (mounted) setState(() => _followStatus = status);
    }
    return profile;
  }

  Future<void> _toggleFollow(SocialProfile profile) async {
    if (_updatingFollow) return;
    setState(() => _updatingFollow = true);
    try {
      if (_followStatus == 'accepted' || _followStatus == 'pending') {
        final shouldReduceCount = _followStatus == 'accepted';
        await _service.removeFollow(profile.userId);
        if (mounted) {
          setState(() {
            _followStatus = 'none';
            if (shouldReduceCount) {
              final currentCount =
                  _followerCountOverride ?? profile.followerCount;
              _followerCountOverride = currentCount > 0 ? currentCount - 1 : 0;
            }
          });
        }
      } else {
        await _service.requestFollow(profile.userId);
        if (mounted) {
          setState(() {
            _followStatus = 'accepted';
            final currentCount =
                _followerCountOverride ?? profile.followerCount;
            _followerCountOverride = currentCount + 1;
          });
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow: $error')),
      );
    } finally {
      if (mounted) setState(() => _updatingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.watch<UserRoleProvider>().userProfile?.uid;

    return AppScaffold(
      title: 'Public Profile',
      showBottomMenu: true,
      body: FutureBuilder<SocialProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data;
          if (profile == null) {
            return _EmptyProfileState(
              onRetry: () => setState(() => _profileFuture = _loadProfile()),
            );
          }

          final isOwnProfile = profile.userId == currentUserId;
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _profileFuture = _loadProfile());
              await _profileFuture;
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              children: [
                _ProfileHeader(
                  profile: profile,
                  followerCount:
                      _followerCountOverride ?? profile.followerCount,
                  showFollowingCount: isOwnProfile,
                ),
                const SizedBox(height: 18),
                if (profile.bio.trim().isNotEmpty)
                  _InfoSection(
                    icon: Icons.auto_stories_outlined,
                    title: 'About',
                    body: profile.bio.trim(),
                  ),
                if (profile.churchName.trim().isNotEmpty)
                  _InfoSection(
                    icon: Icons.church_outlined,
                    title: 'Church',
                    body: profile.churchName.trim(),
                  ),
                const SizedBox(height: 16),
                if (isOwnProfile)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pushNamed('/edit_public_profile')
                        .then((_) {
                      if (mounted) {
                        setState(() => _profileFuture = _loadProfile());
                      }
                    }),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Public Profile'),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed:
                        _updatingFollow ? null : () => _toggleFollow(profile),
                    icon: Icon(
                      _followStatus == 'accepted'
                          ? Icons.person_remove_outlined
                          : Icons.person_add_alt_1_outlined,
                    ),
                    label: Text(
                      _followStatus == 'accepted'
                          ? 'Following'
                          : _followStatus == 'pending'
                              ? 'Requested'
                              : 'Follow',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: profile.acceptsMessages
                        ? () => Navigator.of(context).pushNamed('/inbox')
                        : null,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Public Posts',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 12),
                _PublicPostsList(postsFuture: _postsFuture),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.followerCount,
    required this.showFollowingCount,
  });

  final SocialProfile profile;
  final int followerCount;
  final bool showFollowingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = profile.displayName.trim().isEmpty
        ? '?'
        : profile.displayName.characters.first.toUpperCase();

    return Column(
      children: [
        GestureDetector(
          onTap: profile.avatarUrl.trim().isEmpty
              ? null
              : () => showProfilePhotoViewer(
                    context: context,
                    imageUrl: profile.avatarUrl,
                    displayName: profile.displayName,
                  ),
          child: CircleAvatar(
            radius: 48,
            backgroundImage: profile.avatarUrl.isNotEmpty
                ? NetworkImage(profile.avatarUrl)
                : null,
            child: profile.avatarUrl.isEmpty
                ? Text(initial, style: theme.textTheme.headlineMedium)
                : null,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          profile.displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(
              icon: Icons.people_outline,
              label: '$followerCount followers',
            ),
            if (showFollowingCount)
              _StatChip(
                icon: Icons.person_add_alt_outlined,
                label: '${profile.followingCount} following',
              ),
          ],
        ),
      ],
    );
  }
}

class _PublicPostsList extends StatelessWidget {
  const _PublicPostsList({required this.postsFuture});

  final Future<List<Post>> postsFuture;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Post>>(
      future: postsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text(
            'Could not load public posts.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }

        final posts = snapshot.data ?? const <Post>[];
        if (posts.isEmpty) {
          return _InfoSection(
            icon: Icons.feed_outlined,
            title: 'No public posts yet',
            body: 'Public posts will appear here.',
          );
        }

        return Column(
          children: [
            for (final post in posts)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).pushNamed(
                      '/community_post?entityTable=community_posts&entityId=${Uri.encodeComponent(post.id)}',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  post.content.isEmpty
                                      ? 'Shared a post'
                                      : post.content,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatPostDate(post.timestamp),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          _PublicPostPreview(post: post),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PublicPostPreview extends StatelessWidget {
  const _PublicPostPreview({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaUrl = post.mediaUrl?.trim() ?? '';
    final mediaType = post.mediaType?.toLowerCase() ?? '';
    final isVideo = mediaType.startsWith('video');

    Widget child;
    if (mediaUrl.isEmpty) {
      child = Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else if (isVideo) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.colorScheme.primaryContainer),
          Center(
            child: Icon(
              Icons.play_circle_outline,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      );
    } else {
      child = Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_not_supported_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerHighest,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: child),
              if (isVideo)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.videocam_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatPostDate(DateTime date) {
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
        ),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(body),
        ),
      ),
    );
  }
}

class _EmptyProfileState extends StatelessWidget {
  const _EmptyProfileState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_search_outlined, size: 54),
            const SizedBox(height: 12),
            const Text('This public profile is not available yet.'),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
