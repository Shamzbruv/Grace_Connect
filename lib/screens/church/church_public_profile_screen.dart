import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/church_model.dart';
import '../../models/post.dart';
import '../../providers/user_role_provider.dart';
import '../../services/community_service.dart';
import '../../services/membership_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../live_streaming/live_streaming_screen.dart';

class ChurchPublicProfileScreen extends StatefulWidget {
  const ChurchPublicProfileScreen({
    super.key,
    required this.church,
    this.onViewFeed,
  });

  final Church church;
  final VoidCallback? onViewFeed;

  @override
  State<ChurchPublicProfileScreen> createState() =>
      _ChurchPublicProfileScreenState();
}

class _ChurchPublicProfileScreenState extends State<ChurchPublicProfileScreen> {
  late Future<List<Post>> _postsFuture;
  bool _requestingVisit = false;

  String get _churchId => widget.church.placeId.trim().isNotEmpty
      ? widget.church.placeId.trim()
      : widget.church.id.trim();

  @override
  void initState() {
    super.initState();
    _postsFuture = CommunityService().fetchPublicPostsForChurch(_churchId);
  }

  Future<void> _requestVisit() async {
    if (_requestingVisit || _churchId.isEmpty) return;
    setState(() => _requestingVisit = true);
    try {
      await MembershipService().requestMembership(
        churchId: _churchId,
        message:
            'Visit request from a Grace Connect church discovery profile viewer.',
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Visit request sent to ${widget.church.name}.',
        type: AppFeedbackType.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not send visit request: $error',
        type: AppFeedbackType.error,
      );
    } finally {
      if (mounted) setState(() => _requestingVisit = false);
    }
  }

  void _openLive() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveStreamingScreen(churchId: _churchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final church = widget.church;
    final canRequestVisit =
        context.watch<UserRoleProvider>().userProfile?.placeId.trim().isEmpty ??
            true;
    return AppScaffold(
      title: church.name,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 110),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.16),
                      child: Icon(
                        Icons.church_outlined,
                        color: theme.colorScheme.primary,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            church.name,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (church.denomination.trim().isNotEmpty)
                            Text(
                              church.denomination.trim(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (church.about.trim().isNotEmpty)
                  Text(church.about.trim())
                else
                  Text(
                    'View public posts, live services, and church information before requesting a visit.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 16),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: church.address.trim().isEmpty
                      ? 'Address not listed'
                      : church.address.trim(),
                ),
                if (church.serviceTimesNote.trim().isNotEmpty)
                  _InfoRow(
                    icon: Icons.schedule_outlined,
                    label: church.serviceTimesNote.trim(),
                  ),
                if (church.websiteUrl.trim().isNotEmpty)
                  _InfoRow(
                    icon: Icons.language_outlined,
                    label: church.websiteUrl.trim(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (canRequestVisit)
                FilledButton.icon(
                  onPressed: _requestingVisit ? null : _requestVisit,
                  icon: _requestingVisit
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_reg_outlined),
                  label: const Text('Request Visit'),
                ),
              if (church.isLive && church.liveIsPublic)
                FilledButton.tonalIcon(
                  onPressed: _openLive,
                  icon: const Icon(Icons.live_tv_outlined),
                  label: const Text('Watch Live'),
                ),
              if (widget.onViewFeed != null)
                OutlinedButton.icon(
                  onPressed: widget.onViewFeed,
                  icon: const Icon(Icons.dynamic_feed_outlined),
                  label: const Text('Public Feed'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Public Posts',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Post>>(
            future: _postsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const AppCard(child: AppLoader());
              }
              final posts = snapshot.data ?? const [];
              if (posts.isEmpty) {
                return const AppCard(
                  child: Text('No public posts from this church yet.'),
                );
              }
              return Column(
                children: [
                  for (final post in posts.take(12)) ...[
                    _ChurchPostTile(post: post),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _ChurchPostTile extends StatelessWidget {
  const _ChurchPostTile({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final mediaUrl = post.mediaUrl?.trim() ?? '';
    final isVideo = post.mediaType == 'video';
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 78,
              height: 78,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.55),
              child: mediaUrl.isEmpty
                  ? const Icon(Icons.dynamic_feed_outlined)
                  : isVideo
                      ? const Icon(Icons.play_circle_outline, size: 34)
                      : Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.image_not_supported_outlined),
                        ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.content.trim().isEmpty
                      ? 'Shared a post'
                      : post.content.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${post.likes.length} likes',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
