import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
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
    final roleProvider = context.watch<UserRoleProvider>();
    final profile = roleProvider.userProfile;
    final capabilities = profile?.capabilities;
    final canAccessCareCases = capabilities?.canManageCareCases == true ||
        capabilities?.canViewAssignedCareCases == true;
    final canManagePrayers = capabilities?.canAssignPrayers == true ||
        capabilities?.canViewSensitivePrayers == true;
    final canManageRoles = capabilities?.canManageRoles ?? false;
    final canManageSchedules = capabilities?.canManageSchedules ?? false;
    final canManageLive = capabilities?.canManageMediaUploads == true ||
        profile?.isDeveloper == true;
    final canViewAnalytics = capabilities?.canManageMembersBasic == true ||
        capabilities?.canViewFinance == true ||
        capabilities?.canApproveHighImpactEvents == true ||
        roleProvider.isDeveloper;
    final isPlainMember = _isPlainMember(profile);

    final actions = [
      if (!isPlainMember)
        const _MoreAction('Member View', '/member_view', Icons.home_outlined),
      const _MoreAction('Members', '/members', Icons.people_outline),
      const _MoreAction('Inbox', '/inbox', Icons.inbox_outlined),
      const _MoreAction(
          'Attendance', '/attendance', Icons.checklist_rtl_outlined),
      const _MoreAction(
          'Transfer', '/church_transfer', Icons.compare_arrows_outlined),
      const _MoreAction(
          'Announcements', '/announcements', Icons.campaign_outlined),
      if (canManageSchedules)
        const _MoreAction(
          'Schedules',
          '/schedule_management',
          Icons.event_available_outlined,
        ),
      const _MoreAction(
          'Testimonies', '/testimonies', Icons.auto_awesome_outlined),
      const _MoreAction('Ministries', '/ministries', Icons.groups_outlined),
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
      if (canManageLive)
        const _MoreAction(
          'Manage Live',
          '/admin/live_stream',
          Icons.settings_input_antenna_outlined,
        ),
      if (canViewAnalytics)
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
          for (final action in actions) ...[
            _MoreActionTile(action: action),
            const SizedBox(height: 8),
          ],
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

  bool _isPlainMember(UserProfile? profile) {
    if (profile == null) return true;
    final capabilities = profile.capabilities;
    final hasElevatedAccess = capabilities.canCreateEvents ||
        capabilities.canEditEvents ||
        capabilities.canPublishAnnouncements ||
        capabilities.canModeratePosts ||
        capabilities.canManageSchedules ||
        capabilities.canAssignPrayers ||
        capabilities.canViewSensitivePrayers ||
        capabilities.canManageCareCases ||
        capabilities.canViewAssignedCareCases ||
        capabilities.canManageMembersBasic ||
        capabilities.canManageRoles ||
        capabilities.canViewFinance ||
        capabilities.canManageFinance ||
        capabilities.canManageMediaUploads ||
        capabilities.canManageServiceChecklists ||
        capabilities.canApproveHighImpactEvents ||
        profile.isDeveloper;
    if (hasElevatedAccess) return false;

    return profile.roles.every((role) {
      final normalized = role
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      return normalized.isEmpty || normalized == 'member';
    });
  }
}

class _MoreAction {
  const _MoreAction(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}

class _MoreActionTile extends StatelessWidget {
  const _MoreActionTile({required this.action});

  final _MoreAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(action.icon, color: theme.colorScheme.primary),
      title: Text(
        action.label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      tileColor: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      onTap: () => Navigator.of(context).pushNamed(action.route),
    );
  }
}
