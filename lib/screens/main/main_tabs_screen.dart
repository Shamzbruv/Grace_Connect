import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../access/app_access_context.dart';
import '../../access/app_feature.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/feed_scroll_service.dart';
import '../../widgets/app_bottom_menu.dart';
import '../../widgets/main_tab_scope.dart';
import '../bible/bible_home_screen.dart';
import '../community/community_feed_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/variants/unconnected_dashboard.dart';
import '../events/events_screen.dart';

class MainTabsScreen extends StatefulWidget {
  const MainTabsScreen({
    super.key,
    this.initialIndex = 0,
    this.membershipLimited = false,
    this.limitedTitle,
    this.limitedMessage,
    this.showFindChurchAction = true,
  });

  final int initialIndex;
  final bool membershipLimited;
  final String? limitedTitle;
  final String? limitedMessage;
  final bool showFindChurchAction;

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  static const List<AppFeature> _primaryFeatures = [
    AppFeature.communityRead,
    AppFeature.publicEvents,
    AppFeature.appShell,
    AppFeature.bibleReading,
    AppFeature.appShell,
  ];

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
    final access = _readAccess();
    final feature = _primaryFeatures[index];
    if (access != null && !access.canUse(feature)) {
      _showUnavailableNotice(access, feature);
      return;
    }

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

  AppAccessContext? _readAccess() {
    try {
      return context.read<AppAccessContext>();
    } catch (_) {
      return null;
    }
  }

  void _showUnavailableNotice(AppAccessContext access, AppFeature feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(access.unavailableMessageFor(feature)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppAccessContext? access;
    try {
      access = context.watch<AppAccessContext>();
    } catch (_) {
      access = null;
    }

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
              final currentAccess = _readAccess();
              final feature = _primaryFeatures[index];
              if (currentAccess != null && !currentAccess.canUse(feature)) {
                _pageController.jumpToPage(_currentIndex);
                _showUnavailableNotice(currentAccess, feature);
                return;
              }
              setState(() => _currentIndex = index);
            },
            children: [
              CommunityFeedScreen(
                showBottomMenu: false,
                showFindChurchAction: widget.showFindChurchAction,
              ),
              const EventsScreen(showBottomMenu: false),
              access == null || access.hasActiveChurchSubscription
                  ? const DashboardScreen()
                  : UnconnectedDashboard(access: access),
              BibleHomeScreen(
                showBottomNavigation: false,
                allowDailyQuiz: access?.hasActiveChurchSubscription ?? true,
              ),
              _MoreTabScreen(
                access: access,
              ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomMenu(
          selectedIndex: _currentIndex,
          onDestinationSelected: _setTab,
          access: access,
        ),
      ),
    );
  }
}

class _MoreTabScreen extends StatelessWidget {
  const _MoreTabScreen({
    required this.access,
  });

  final AppAccessContext? access;

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
        const _MoreAction(
          'Member View',
          '/member_view',
          Icons.home_outlined,
          AppFeature.churchHome,
        ),
      const _MoreAction(
        'Members',
        '/members',
        Icons.people_outline,
        AppFeature.memberDirectory,
      ),
      const _MoreAction(
        'Inbox',
        '/inbox',
        Icons.inbox_outlined,
        AppFeature.directMessages,
      ),
      const _MoreAction(
        'Attendance',
        '/attendance',
        Icons.checklist_rtl_outlined,
        AppFeature.attendance,
      ),
      const _MoreAction(
        'Transfer',
        '/church_transfer',
        Icons.compare_arrows_outlined,
        AppFeature.churchTransfer,
      ),
      const _MoreAction(
        'Announcements',
        '/announcements',
        Icons.campaign_outlined,
        AppFeature.announcements,
      ),
      if (canManageSchedules)
        const _MoreAction(
          'Schedules',
          '/schedule_management',
          Icons.event_available_outlined,
          AppFeature.scheduling,
        ),
      const _MoreAction(
        'Testimonies',
        '/testimonies',
        Icons.auto_awesome_outlined,
        AppFeature.churchTestimonies,
      ),
      const _MoreAction(
        'Ministries',
        '/ministries',
        Icons.groups_outlined,
        AppFeature.ministryManagement,
      ),
      _MoreAction(
        canManagePrayers ? 'Prayer Requests' : 'Prayers',
        '/prayers',
        Icons.volunteer_activism_outlined,
        AppFeature.privatePrayerCare,
      ),
      _MoreAction(
        canAccessCareCases ? 'Care Cases' : 'Counseling',
        '/counseling',
        Icons.favorite_outline,
        AppFeature.counseling,
      ),
      const _MoreAction(
        'Live',
        '/live_streaming',
        Icons.live_tv_outlined,
        AppFeature.communityRead,
      ),
      if (canManageLive)
        const _MoreAction(
          'Manage Live',
          '/admin/live_stream',
          Icons.settings_input_antenna_outlined,
          AppFeature.liveManagement,
        ),
      if (canViewAnalytics)
        const _MoreAction(
          'Analytics',
          '/analytics',
          Icons.analytics_outlined,
          AppFeature.churchAnalytics,
        ),
      if (canManageRoles)
        const _MoreAction(
          'Roles',
          '/role_management',
          Icons.security_outlined,
          AppFeature.roleManagement,
        ),
      const _MoreAction(
        'Giving',
        '/donations',
        Icons.favorite_outline,
        AppFeature.churchFinance,
      ),
      const _MoreAction(
        'Notifications',
        '/notifications',
        Icons.notifications_outlined,
        AppFeature.notifications,
      ),
      const _MoreAction(
        'Grace Rooms',
        '/grace_rooms',
        Icons.volunteer_activism_outlined,
        AppFeature.graceRooms,
      ),
      const _MoreAction(
        'Grace Circles',
        '/grace_circles',
        Icons.diversity_3_outlined,
        AppFeature.graceCircles,
      ),
      const _MoreAction(
        'Saved',
        '/saved',
        Icons.bookmarks_outlined,
        AppFeature.savedItems,
      ),
      const _MoreAction(
        'Public Profile',
        '/public_profile',
        Icons.person_pin_circle_outlined,
        AppFeature.socialProfile,
      ),
      const _MoreAction(
        'Settings',
        '/settings',
        Icons.settings_outlined,
        AppFeature.appShell,
      ),
      const _MoreAction(
        'Profile',
        '/profile',
        Icons.person_outline,
        AppFeature.appShell,
      ),
      const _MoreAction(
        'Support',
        '/support',
        Icons.support_agent_outlined,
        AppFeature.appShell,
      ),
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
            _MoreActionTile(
              action: action,
              locked: access != null && !access!.canUse(action.feature),
              lockedMessage: access?.unavailableMessageFor(action.feature),
            ),
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
  const _MoreAction(this.label, this.route, this.icon, this.feature);

  final String label;
  final String route;
  final IconData icon;
  final AppFeature feature;
}

class _MoreActionTile extends StatelessWidget {
  const _MoreActionTile({
    required this.action,
    required this.locked,
    this.lockedMessage,
  });

  final _MoreAction action;
  final bool locked;
  final String? lockedMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = locked;
    final isGraceRooms = action.route == '/grace_rooms';
    final foreground = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : isGraceRooms
            ? theme.colorScheme.secondary
            : theme.colorScheme.primary;

    return ListTile(
      leading: isGraceRooms
          ? Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: disabled
                    ? theme.colorScheme.surfaceContainerHighest
                    : foreground.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: disabled
                      ? theme.dividerColor.withValues(alpha: 0.12)
                      : foreground.withValues(alpha: 0.32),
                ),
              ),
              child: Icon(action.icon, color: foreground),
            )
          : Icon(action.icon, color: foreground),
      title: Text(
        action.label,
        style: theme.textTheme.titleMedium?.copyWith(
          color: disabled ? foreground : null,
          fontWeight: isGraceRooms ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      trailing: Icon(
        disabled ? Icons.lock_outline : Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      tileColor: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.12)),
      ),
      enabled: true,
      onTap: disabled
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lockedMessage ?? '${action.label} is not available yet.',
                  ),
                ),
              );
            }
          : () => Navigator.of(context).pushNamed(action.route),
    );
  }
}
