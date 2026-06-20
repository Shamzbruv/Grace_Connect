import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/app_notification.dart';
import '../../models/bible_nudge.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/bible_nudge_service.dart';
import '../../services/community_service.dart';
import '../../services/direct_message_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../community/post_detail_screen.dart';
import '../messages/message_thread_screen.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_scaffold.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final service = NotificationService();
    final communityService = CommunityService();

    return AppScaffold(
      title: 'Notifications',
      actions: [
        if (user != null)
          TextButton(
            onPressed: () => service.markAllAsRead(user.uid),
            child: const Text('Mark all read'),
          ),
      ],
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<AppNotification>>(
              stream: service.watchNotifications(user.uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child:
                        Text('Could not load notifications: ${snapshot.error}'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final notifications = snapshot.data ?? const [];
                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_none_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No notifications yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return _NotificationTile(
                      notification: notification,
                      onTap: () async {
                        await _openNotification(
                          context,
                          service,
                          communityService,
                          notification,
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    NotificationService notificationService,
    CommunityService communityService,
    AppNotification notification,
  ) async {
    await notificationService.markAsRead(notification.id);
    if (!context.mounted) return;

    final isPostNotification =
        notification.type == 'like' || notification.type == 'comment';
    final isCommunityEntity = notification.entityTable == 'community_posts' ||
        notification.entityTable == 'community_comments';

    if (isPostNotification || isCommunityEntity) {
      try {
        final post = await communityService.fetchPostForNotification(
          entityTable: notification.entityTable,
          entityId: notification.entityId,
        );
        if (!context.mounted) return;
        if (post != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PostDetailScreen(post: post),
            ),
          );
          return;
        }
        AppFeedback.show(
          context,
          'That post is no longer available.',
          type: AppFeedbackType.warning,
        );
        return;
      } catch (error) {
        if (!context.mounted) return;
        AppFeedback.show(
          context,
          'Could not open post: $error',
          type: AppFeedbackType.error,
        );
        return;
      }
    }

    if (notification.type == 'bible_nudge_response' &&
        notification.entityTable == 'bible_nudges' &&
        notification.entityId?.isNotEmpty == true) {
      await _openBibleNudgeMessageThread(context, notification);
      return;
    }

    final route = notification.route;
    if (route != null && route.isNotEmpty && context.mounted) {
      Navigator.pushNamed(context, route);
    }
  }

  Future<void> _openBibleNudgeMessageThread(
    BuildContext context,
    AppNotification notification,
  ) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    if (currentUser == null) return;

    try {
      final nudge =
          await BibleNudgeService().getNudge(notification.entityId ?? '');
      if (!context.mounted) return;
      if (nudge != null && nudge.status != 'accepted') {
        Navigator.pushNamed(context, notification.route ?? '/notifications');
        return;
      }

      final otherUser = await _resolveBibleNudgeOtherUser(
        currentUser: currentUser,
        notification: notification,
        nudge: nudge,
      );
      if (!context.mounted) return;
      if (otherUser == null) {
        AppFeedback.show(
          context,
          'That member profile could not be opened.',
          type: AppFeedbackType.warning,
        );
        return;
      }

      final conversation = await DirectMessageService().getOrCreateConversation(
        currentUser: currentUser,
        otherUser: otherUser,
      );
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageThreadScreen(
            conversation: conversation,
            otherUser: otherUser,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      AppFeedback.show(
        context,
        'Could not open message: $error',
        type: AppFeedbackType.error,
      );
    }
  }

  Future<UserProfile?> _resolveBibleNudgeOtherUser({
    required UserProfile currentUser,
    required AppNotification notification,
    BibleNudge? nudge,
  }) async {
    final userService = UserService();
    final candidateIds = <String>[
      if (notification.actorId?.trim().isNotEmpty == true)
        notification.actorId!.trim(),
      if (nudge != null && currentUser.uid == nudge.senderId) nudge.recipientId,
      if (nudge != null && currentUser.uid == nudge.recipientId) nudge.senderId,
      if (nudge != null) nudge.recipientId,
      if (nudge != null) nudge.senderId,
    ];

    for (final id in candidateIds) {
      if (id.isEmpty || id == currentUser.uid) continue;
      final profile = await userService.getUserProfile(id);
      if (profile != null) return profile;
    }

    final candidateNames = <String>[
      if (nudge?.recipientName.trim().isNotEmpty == true)
        nudge!.recipientName.trim(),
      if (nudge?.senderName.trim().isNotEmpty == true) nudge!.senderName.trim(),
      if (notification.actorName.trim().isNotEmpty)
        notification.actorName.trim(),
      _nameFromBibleNudgeBody(notification.body),
    ].where((name) => name.isNotEmpty).toSet();

    for (final name in candidateNames) {
      final profile = await userService.findBestPersonMatch(name);
      if (profile != null && profile.uid != currentUser.uid) return profile;
    }

    if (nudge?.status == 'accepted') {
      final fallbackId = candidateIds.firstWhere(
        (id) => id.isNotEmpty && id != currentUser.uid,
        orElse: () => '',
      );
      if (fallbackId.isNotEmpty) {
        return UserProfile(
          uid: fallbackId,
          email: '',
          fullName: _fallbackBibleNudgeName(currentUser, notification, nudge),
          phoneNumber: '',
          placeId: nudge?.churchId ?? currentUser.churchId,
          placeName: '',
          roles: const ['Member'],
          joinDate: DateTime.now(),
          allowMessages: true,
        );
      }
    }

    return null;
  }

  String _fallbackBibleNudgeName(
    UserProfile currentUser,
    AppNotification notification,
    BibleNudge? nudge,
  ) {
    if (nudge != null) {
      if (currentUser.uid == nudge.senderId &&
          nudge.recipientName.trim().isNotEmpty) {
        return nudge.recipientName.trim();
      }
      if (currentUser.uid == nudge.recipientId &&
          nudge.senderName.trim().isNotEmpty) {
        return nudge.senderName.trim();
      }
    }
    if (notification.actorName.trim().isNotEmpty) {
      return notification.actorName.trim();
    }
    final bodyName = _nameFromBibleNudgeBody(notification.body);
    return bodyName.isNotEmpty ? bodyName : 'Member';
  }

  String _nameFromBibleNudgeBody(String body) {
    final acceptedIndex = body.toLowerCase().indexOf(' accepted');
    if (acceptedIndex <= 0) return '';
    return body.substring(0, acceptedIndex).trim();
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unreadColor = theme.colorScheme.primary.withValues(alpha: 0.12);

    return Material(
      color: notification.isRead ? theme.cardTheme.color : unreadColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.16),
                child: Icon(
                  _iconForType(notification.type),
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(notification.body),
                    const SizedBox(height: 6),
                    Text(
                      timeago.format(notification.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (notification.type == 'bible_nudge_request' &&
                        notification.entityId?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      _BibleNudgeActions(
                        notification: notification,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'like' => Icons.favorite_outline,
      'comment' => Icons.mode_comment_outlined,
      'announcement' => Icons.campaign_outlined,
      'pastor_event' => Icons.campaign_outlined,
      'prayer_request' => Icons.volunteer_activism_outlined,
      'counseling_request' => Icons.favorite_outline,
      'counseling_assignment' => Icons.support_agent_outlined,
      'family_request' => Icons.family_restroom_outlined,
      'family_response' => Icons.how_to_reg_outlined,
      'bible_nudge_request' => Icons.menu_book_outlined,
      'bible_nudge_response' => Icons.mark_chat_read_outlined,
      _ => Icons.notifications_outlined,
    };
  }
}

class _BibleNudgeActions extends StatefulWidget {
  const _BibleNudgeActions({required this.notification});

  final AppNotification notification;

  @override
  State<_BibleNudgeActions> createState() => _BibleNudgeActionsState();
}

class _BibleNudgeActionsState extends State<_BibleNudgeActions> {
  final BibleNudgeService _service = BibleNudgeService();
  BibleNudge? _nudge;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final nudge = await _service.getNudge(widget.notification.entityId ?? '');
    if (!mounted) return;
    setState(() {
      _nudge = nudge;
      _isLoading = false;
    });
  }

  Future<void> _respond(bool accepted) async {
    final nudge = _nudge;
    if (nudge == null) return;
    setState(() => _isSaving = true);
    try {
      await _service.respondToNudge(nudge: nudge, accepted: accepted);
      await NotificationService().markAsRead(widget.notification.id);
      if (!mounted) return;
      AppFeedback.show(
        context,
        accepted ? 'Bible Nudge accepted.' : 'Bible Nudge declined.',
        type: accepted ? AppFeedbackType.success : AppFeedbackType.info,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not respond: $error',
        type: AppFeedbackType.error,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nudge = _nudge;
    if (_isLoading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (nudge == null || nudge.status != 'pending') {
      return Text(
        nudge == null
            ? 'Bible Nudge unavailable.'
            : 'Response: ${nudge.status}',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => _respond(false),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            onPressed: _isSaving ? null : () => _respond(true),
            child: const Text('Accept'),
          ),
        ),
      ],
    );
  }
}
