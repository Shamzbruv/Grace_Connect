import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_role_provider.dart';
import '../../services/community_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'post_detail_screen.dart';

class CommunityNotificationRouteScreen extends StatefulWidget {
  const CommunityNotificationRouteScreen({
    super.key,
    required this.entityTable,
    required this.entityId,
  });

  final String entityTable;
  final String entityId;

  @override
  State<CommunityNotificationRouteScreen> createState() =>
      _CommunityNotificationRouteScreenState();
}

class _CommunityNotificationRouteScreenState
    extends State<CommunityNotificationRouteScreen> {
  late Future<Widget> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Widget> _load() async {
    final user = context.read<UserRoleProvider>().userProfile;
    if (user != null &&
        widget.entityTable.trim().isNotEmpty &&
        widget.entityId.trim().isNotEmpty) {
      await NotificationService().markEntityAsRead(
        userId: user.uid,
        entityTable: widget.entityTable.trim(),
        entityId: widget.entityId.trim(),
      );
    }

    final post = await CommunityService().fetchPostForNotification(
      entityTable: widget.entityTable,
      entityId: widget.entityId,
    );
    if (post != null) return PostDetailScreen(post: post);
    return const _MissingPostView();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppScaffold(
            title: 'Post',
            body: Center(child: AppLoader()),
          );
        }
        if (snapshot.hasError) {
          return AppScaffold(
            title: 'Post',
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not open post: ${snapshot.error}'),
              ),
            ),
          );
        }
        return snapshot.data ?? const _MissingPostView();
      },
    );
  }
}

class _MissingPostView extends StatelessWidget {
  const _MissingPostView();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Post',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.link_off_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'That post is no longer available.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  AppFeedback.show(context, 'Opening community feed.');
                  Navigator.of(context).pushReplacementNamed('/community');
                },
                icon: const Icon(Icons.forum_outlined),
                label: const Text('Open Community'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
