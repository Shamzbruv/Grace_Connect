import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_subscription_service.dart';
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
  late final PageController _pageController;
  late int _currentIndex;
  bool _subscriptionLimited = false;

  bool get _hasLimitedAccess =>
      widget.membershipLimited || _subscriptionLimited;

  Set<int> get _allowedPrimaryIndexes {
    if (widget.membershipLimited) return const {0};
    if (_subscriptionLimited) return const {3};
    return const {0, 1, 2, 3, 4};
  }

  Set<String> get _allowedRoutes {
    if (widget.membershipLimited) return const {'/community'};
    if (_subscriptionLimited) return const {'/bible', '/daily_word'};
    return const {};
  }

  String get _limitedNotice {
    if (widget.membershipLimited) {
      return widget.limitedMessage ??
          'Your church access is not active yet. You can browse the public feed, but member tools unlock after church approval.';
    }
    return 'This church subscription is not active. Bible reading and Daily Word are available, but church tools are paused. Please contact your church admin about subscription options.';
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    _pageController = PageController(initialPage: _currentIndex);
    _loadSubscriptionState();
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
    if (_hasLimitedAccess && !_allowedPrimaryIndexes.contains(index)) {
      _showLimitedNotice();
      return;
    }
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadSubscriptionState() async {
    if (widget.membershipLimited) {
      if (!mounted) return;
      setState(() {
        _subscriptionLimited = false;
        _currentIndex = 0;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      return;
    }

    final contextResult =
        await ChurchSubscriptionService().getCurrentChurchSubscription();
    if (!mounted) return;

    final limited = !contextResult.isActive;
    setState(() {
      _subscriptionLimited = limited;
      if (limited) _currentIndex = 3;
    });

    if (limited && _pageController.hasClients) {
      _pageController.jumpToPage(3);
    }
  }

  void _showLimitedNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_limitedNotice),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        final fallbackIndex = _allowedPrimaryIndexes.first;
        if (didPop || _currentIndex == fallbackIndex) return;
        _setTab(fallbackIndex);
      },
      child: Scaffold(
        body: MainTabScope(
          inTabShell: true,
          child: PageView(
            controller: _pageController,
            physics:
                _hasLimitedAccess ? const NeverScrollableScrollPhysics() : null,
            onPageChanged: (index) {
              if (_hasLimitedAccess &&
                  !_allowedPrimaryIndexes.contains(index)) {
                _pageController.jumpToPage(_allowedPrimaryIndexes.first);
                _showLimitedNotice();
                return;
              }
              setState(() => _currentIndex = index);
            },
            children: [
              CommunityFeedScreen(
                showBottomMenu: false,
                limitedAccessTitle: widget.limitedTitle,
                limitedAccessMessage: widget.limitedMessage,
                showFindChurchAction: widget.showFindChurchAction,
              ),
              const EventsScreen(showBottomMenu: false),
              const DashboardScreen(),
              BibleHomeScreen(
                showBottomNavigation: false,
                allowDailyQuiz: !_subscriptionLimited,
              ),
              _MoreTabScreen(
                subscriptionLimited: _hasLimitedAccess,
                limitedAllowedRoutes: _allowedRoutes,
                limitedNotice: _limitedNotice,
              ),
            ],
          ),
        ),
        bottomNavigationBar: AppBottomMenu(
          selectedIndex: _currentIndex,
          onDestinationSelected: _setTab,
          subscriptionLimited: _hasLimitedAccess,
          limitedAllowedIndexes: _allowedPrimaryIndexes,
          limitedAllowedRoutes: _allowedRoutes,
          limitedNotice: _limitedNotice,
        ),
      ),
    );
  }
}

class _MoreTabScreen extends StatelessWidget {
  const _MoreTabScreen({
    required this.subscriptionLimited,
    required this.limitedAllowedRoutes,
    required this.limitedNotice,
  });

  final bool subscriptionLimited;
  final Set<String> limitedAllowedRoutes;
  final String limitedNotice;

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
        'Notifications',
        '/notifications',
        Icons.notifications_outlined,
      ),
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
            _MoreActionTile(
              action: action,
              subscriptionLimited: subscriptionLimited &&
                  !limitedAllowedRoutes.contains(action.route),
              limitedNotice: limitedNotice,
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
  const _MoreAction(this.label, this.route, this.icon);

  final String label;
  final String route;
  final IconData icon;
}

class _MoreActionTile extends StatelessWidget {
  const _MoreActionTile({
    required this.action,
    required this.subscriptionLimited,
    required this.limitedNotice,
  });

  final _MoreAction action;
  final bool subscriptionLimited;
  final String limitedNotice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = subscriptionLimited;
    final foreground = disabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : theme.colorScheme.primary;

    return ListTile(
      leading: Icon(action.icon, color: foreground),
      title: Text(
        action.label,
        style: theme.textTheme.titleMedium?.copyWith(
          color: disabled ? foreground : null,
          fontWeight: FontWeight.w700,
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
                SnackBar(content: Text(limitedNotice)),
              );
            }
          : () => Navigator.of(context).pushNamed(action.route),
    );
  }
}
