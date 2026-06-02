import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/user_role_provider.dart';
import '../../services/feed_scroll_service.dart';
import '../../widgets/app_bottom_menu.dart';
import '../../widgets/main_tab_scope.dart';
import '../bible/bible_home_screen.dart';
import '../community/community_feed_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../events/events_screen.dart';

class MainTabsScreen extends StatefulWidget {
  const MainTabsScreen({
    super.key,
    this.initialIndex = 0,
  });

  final int initialIndex;

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setTab(int index) {
    if (index == _currentIndex) {
      if (index == 0) FeedScrollService.requestScrollToTop();
      return;
    }
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _currentIndex == 0) return;
        _setTab(0);
      },
      child: Scaffold(
        body: MainTabScope(
          inTabShell: true,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            children: const [
              CommunityFeedScreen(showBottomMenu: false),
              EventsScreen(showBottomMenu: false),
              DashboardScreen(),
              BibleHomeScreen(showBottomNavigation: false),
              _MoreTabScreen(),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomMenu(
          selectedIndex: _currentIndex,
          onDestinationSelected: _setTab,
        ),
      ),
    );
  }
}

class _MoreTabScreen extends StatelessWidget {
  const _MoreTabScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<UserRoleProvider>().userProfile;
    final capabilities = profile?.capabilities;
    final canAccessCareCases = capabilities?.canManageCareCases == true ||
        capabilities?.canViewAssignedCareCases == true;
    final canManagePrayers = capabilities?.canAssignPrayers == true ||
        capabilities?.canViewSensitivePrayers == true;
    final canManageRoles = capabilities?.canManageRoles ?? false;

    final actions = [
      const _MoreAction('Member View', '/member_view', Icons.home_outlined),
      const _MoreAction('Members', '/members', Icons.people_outline),
      const _MoreAction('Inbox', '/inbox', Icons.inbox_outlined),
      const _MoreAction(
          'Attendance', '/attendance', Icons.checklist_rtl_outlined),
      const _MoreAction(
          'Testimonies', '/testimonies', Icons.auto_awesome_outlined),
      _MoreAction(
        canManagePrayers ? 'Prayer Requests' : 'Prayers',
        '/prayers',
        Icons.volunteer_activism_outlined,
      ),
      _MoreAction(
        canAccessCareCases ? 'Care Cases' : 'Counseling',
        '/counseling',
        Icons.favorite_outline,
      ),
      const _MoreAction('Live', '/live_streaming', Icons.live_tv_outlined),
      const _MoreAction('Analytics', '/analytics', Icons.analytics_outlined),
      if (canManageRoles)
        const _MoreAction('Roles', '/role_management', Icons.security_outlined),
      const _MoreAction('Giving', '/donations', Icons.favorite_outline),
      const _MoreAction(
          'Notifications', '/notifications', Icons.notifications_outlined),
      const _MoreAction('Settings', '/settings', Icons.settings_outlined),
      const _MoreAction('Profile', '/profile', Icons.person_outline),
      const _MoreAction('Support', '/support', Icons.support_agent_outlined),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Text(
            'More',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
            ),
            itemBuilder: (context, index) {
              final action = actions[index];
              return InkWell(
                onTap: () => Navigator.of(context).pushNamed(action.route),
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(action.icon, color: theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(
                        action.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (!context.mounted) return;
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (route) => false);
            },
          ),
        ],
      ),
    );
  }
}

class _MoreAction {
  const _MoreAction(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}
