import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_role_provider.dart';
import '../../../services/notification_service.dart';
import '../../../widgets/app_bottom_menu.dart';
import '../../../widgets/inbox_icon_button.dart';
import '../../../widgets/main_tab_scope.dart';

class DashboardScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? fab;

  const DashboardScaffold({
    super.key,
    required this.title,
    required this.children,
    this.fab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProfile = Provider.of<UserRoleProvider>(context).userProfile;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title:
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          const InboxIconButton(),
          StreamBuilder<int>(
            stream: userProfile == null
                ? const Stream<int>.empty()
                : NotificationService().watchUnreadCount(userProfile.uid),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      Navigator.pushNamed(context, '/notifications');
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
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
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/profile'),
              child: CircleAvatar(
                radius: 16,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                backgroundImage: (userProfile?.photoUrl.isNotEmpty ?? false)
                    ? NetworkImage(userProfile!.photoUrl)
                    : null,
                child: (userProfile?.photoUrl.isEmpty ?? true)
                    ? Icon(Icons.person,
                        size: 20, color: theme.colorScheme.primary)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
      floatingActionButton: fab,
      bottomNavigationBar:
          MainTabScope.isInTabShell(context) ? null : const AppBottomMenu(),
    );
  }
}
