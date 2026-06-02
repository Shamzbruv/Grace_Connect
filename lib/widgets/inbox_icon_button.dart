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

    return StreamBuilder<int>(
      stream: user == null
          ? const Stream<int>.empty()
          : DirectMessageService().watchUnreadCount(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Inbox',
              icon: const Icon(Icons.inbox_outlined),
              onPressed: () => Navigator.pushNamed(context, '/inbox'),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
  }
}
