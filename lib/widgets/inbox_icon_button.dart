import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/user_role_provider.dart';
import '../services/direct_message_service.dart';

class InboxIconButton extends StatelessWidget {
  const InboxIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final theme = Theme.of(context);

    final messageService = DirectMessageService();

    return StreamBuilder<int>(
      stream: user == null
          ? const Stream<int>.empty()
          : messageService.watchUnreadCount(),
      builder: (context, messageSnapshot) {
        return StreamBuilder<int>(
          stream: user == null
              ? const Stream<int>.empty()
              : messageService.watchPendingMessageRequestCount(),
          builder: (context, requestSnapshot) {
            final unreadCount =
                (messageSnapshot.data ?? 0) + (requestSnapshot.data ?? 0);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  tooltip: 'Messages and requests',
                  icon: const Icon(Icons.inbox_outlined),
                  onPressed: () => Navigator.pushNamed(context, '/inbox'),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
