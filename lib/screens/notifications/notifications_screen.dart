import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/app_notification.dart';
import '../../models/bible_nudge.dart';
import '../../providers/user_role_provider.dart';
import '../../services/bible_nudge_service.dart';
import '../../services/community_service.dart';
import '../../services/notification_service.dart';
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
    notificationService.openNotification(notification);
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
                    if (notification.type == 'membership_request_received') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.how_to_reg_outlined),
                          label: const Text('Review request'),
                        ),
                      ),
                    ],
                    if (notification.type == 'message_request_received') ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.mark_email_unread_outlined),
                          label: const Text('Review request'),
                        ),
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
      'message_request_received' => Icons.mark_email_unread_outlined,
      'message_request_accepted' => Icons.mark_chat_read_outlined,
      'message_request_denied' => Icons.do_not_disturb_alt_outlined,
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
