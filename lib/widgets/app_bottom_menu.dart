import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../access/app_access_context.dart';
import '../access/app_feature.dart';
import '../models/user_profile.dart';
import '../providers/user_role_provider.dart';
import '../services/feed_scroll_service.dart';

class AppBottomMenu extends StatelessWidget {
  const AppBottomMenu({
    super.key,
    this.selectedIndex,
    this.onDestinationSelected,
    this.subscriptionLimited = false,
    this.limitedAllowedIndexes = const {0},
    this.limitedAllowedRoutes = const {'/community'},
    this.limitedNotice,
    this.access,
  });

  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final bool subscriptionLimited;
  final Set<int> limitedAllowedIndexes;
  final Set<String> limitedAllowedRoutes;
  final String? limitedNotice;
  final AppAccessContext? access;

  static const List<_MenuItem> _primaryItems = [
    _MenuItem(
      label: 'Feed',
      route: '/community',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
      feature: AppFeature.communityRead,
    ),
    _MenuItem(
      label: 'Events',
      route: '/events',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      feature: AppFeature.publicEvents,
    ),
    _MenuItem(
      label: 'Home',
      route: '/dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
      feature: AppFeature.appShell,
    ),
    _MenuItem(
      label: 'Bible',
      route: '/bible',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      feature: AppFeature.bibleReading,
    ),
    _MenuItem(
      label: 'More',
      icon: Icons.more_horiz,
      selectedIcon: Icons.more,
      feature: AppFeature.appShell,
    ),
  ];

  static const List<_MenuItem> _moreItems = [
    _MenuItem(
      label: 'Members',
      route: '/members',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
      feature: AppFeature.memberDirectory,
    ),
    _MenuItem(
      label: 'Announcements',
      route: '/announcements',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
      feature: AppFeature.announcements,
    ),
    _MenuItem(
      label: 'Ministries',
      route: '/ministries',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
      feature: AppFeature.ministryManagement,
    ),
    _MenuItem(
      label: 'Attendance',
      route: '/attendance',
      icon: Icons.checklist_rtl_outlined,
      selectedIcon: Icons.checklist_rtl,
      feature: AppFeature.attendance,
    ),
    _MenuItem(
      label: 'Transfer',
      route: '/church_transfer',
      icon: Icons.compare_arrows_outlined,
      selectedIcon: Icons.compare_arrows,
      feature: AppFeature.churchTransfer,
    ),
    _MenuItem(
      label: 'Prayers',
      route: '/prayers',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism,
      feature: AppFeature.privatePrayerCare,
    ),
    _MenuItem(
      label: 'Counseling',
      route: '/counseling',
      icon: Icons.favorite_outline,
      selectedIcon: Icons.favorite,
      feature: AppFeature.counseling,
    ),
    _MenuItem(
      label: 'Live Streaming',
      route: '/live_streaming',
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
      feature: AppFeature.communityRead,
    ),
    _MenuItem(
      label: 'Manage Live',
      route: '/admin/live_stream',
      icon: Icons.settings_input_antenna_outlined,
      selectedIcon: Icons.settings_input_antenna,
      feature: AppFeature.liveManagement,
    ),
    _MenuItem(
      label: 'Analytics',
      route: '/analytics',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      feature: AppFeature.churchAnalytics,
    ),
    _MenuItem(
      label: 'Notifications',
      route: '/notifications',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      feature: AppFeature.notifications,
    ),
    _MenuItem(
      label: 'Giving',
      route: '/donations',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism,
      feature: AppFeature.churchFinance,
    ),
    _MenuItem(
      label: 'Grace Rooms',
      route: '/grace_rooms',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism,
      feature: AppFeature.graceRooms,
    ),
    _MenuItem(
      label: 'Grace Circles',
      route: '/grace_circles',
      icon: Icons.diversity_3_outlined,
      selectedIcon: Icons.diversity_3,
      feature: AppFeature.graceCircles,
    ),
    _MenuItem(
      label: 'Saved',
      route: '/saved',
      icon: Icons.bookmarks_outlined,
      selectedIcon: Icons.bookmarks,
      feature: AppFeature.savedItems,
    ),
    _MenuItem(
      label: 'Public Profile',
      route: '/public_profile',
      icon: Icons.person_pin_circle_outlined,
      selectedIcon: Icons.person_pin_circle,
      feature: AppFeature.socialProfile,
    ),
    _MenuItem(
      label: 'Settings',
      route: '/settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      feature: AppFeature.appShell,
    ),
    _MenuItem(
      label: 'Profile',
      route: '/profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      feature: AppFeature.appShell,
    ),
    _MenuItem(
      label: 'Support',
      route: '/support',
      icon: Icons.support_agent_outlined,
      selectedIcon: Icons.support_agent,
      feature: AppFeature.appShell,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSelectedIndex = selectedIndex ?? _selectedIndex(context);
    final effectiveAccess = _readAccess(context, listen: true);

    return NavigationBar(
      selectedIndex: effectiveSelectedIndex,
      height: 72,
      backgroundColor: theme.colorScheme.surface,
      indicatorColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.75),
      elevation: 6,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        final item = _primaryItems[index];
        if (_isPrimaryDisabled(index, effectiveAccess)) {
          _showLimitedNotice(context, item.feature, effectiveAccess);
          return;
        }

        final controlledSelection = onDestinationSelected;
        if (controlledSelection != null) {
          controlledSelection(index);
          return;
        }

        final route = item.route;

        if (route == null) {
          _showMoreMenu(context);
          return;
        }

        _navigateTo(context, route, effectiveAccess);
      },
      destinations: [
        for (var index = 0; index < _primaryItems.length; index++)
          NavigationDestination(
            icon: _menuIcon(
              context,
              _primaryItems[index].icon,
              disabled: _isPrimaryDisabled(index, effectiveAccess),
            ),
            selectedIcon: _menuIcon(
              context,
              _primaryItems[index].selectedIcon,
              disabled: _isPrimaryDisabled(index, effectiveAccess),
            ),
            label: _primaryItems[index].label,
          ),
      ],
    );
  }

  Widget _menuIcon(
    BuildContext context,
    IconData icon, {
    required bool disabled,
  }) {
    if (!disabled) return Icon(icon);
    return Opacity(
      opacity: 0.35,
      child: Icon(icon),
    );
  }

  int _selectedIndex(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final primaryIndex =
        _primaryItems.indexWhere((item) => item.route == currentRoute);

    if (primaryIndex >= 0) return primaryIndex;

    if (_isMoreRoute(currentRoute)) {
      return _primaryItems.length - 1;
    }

    return 0;
  }

  bool _isMoreRoute(String? currentRoute) {
    if (currentRoute == null) return false;
    if (currentRoute.startsWith('/settings')) return true;
    return _moreItems.any((item) => item.route == currentRoute);
  }

  void _navigateTo(
    BuildContext context,
    String route, [
    AppAccessContext? effectiveAccess,
  ]) {
    final feature = _featureForRoute(route);
    if (_isRouteDisabled(route,
        feature: feature, accessContext: effectiveAccess)) {
      _showLimitedNotice(context, feature, effectiveAccess);
      return;
    }

    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == route) {
      if (route == '/community') FeedScrollService.requestScrollToTop();
      return;
    }

    Navigator.of(context).pushNamed(route);
  }

  void _showMoreMenu(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final roleProvider = context.read<UserRoleProvider>();
    final items = _visibleMoreItems(roleProvider.userProfile);
    final effectiveAccess = _readAccess(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _MoreMenuSheet(
          items: items,
          currentRoute: currentRoute,
          subscriptionLimited: subscriptionLimited,
          limitedAllowedRoutes: limitedAllowedRoutes,
          limitedNotice: limitedNotice,
          access: effectiveAccess,
          onSelectRoute: (route) {
            Navigator.of(sheetContext).pop();
            _navigateTo(context, route, effectiveAccess);
          },
          onLogOut: () async {
            Navigator.of(sheetContext).pop();
            await Supabase.instance.client.auth.signOut();
            if (context.mounted) {
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (route) => false);
            }
          },
        );
      },
    );
  }

  List<_MenuItem> _visibleMoreItems(UserProfile? profile) {
    return _moreItems.where((item) {
      if (item.route == '/members') return _canViewMembers(profile);
      if (item.route == '/analytics') return _canViewAnalytics(profile);
      if (item.route == '/admin/live_stream') return _canManageLive(profile);
      return true;
    }).toList(growable: false);
  }

  bool _canViewMembers(UserProfile? profile) {
    return profile != null;
  }

  bool _canViewAnalytics(UserProfile? profile) {
    if (profile == null) return false;
    final capabilities = profile.capabilities;
    return profile.isDeveloper ||
        capabilities.canManageMembersBasic ||
        capabilities.canViewFinance ||
        capabilities.canApproveHighImpactEvents;
  }

  bool _canManageLive(UserProfile? profile) {
    if (profile == null) return false;
    return profile.isDeveloper || profile.capabilities.canManageMediaUploads;
  }

  bool _isPrimaryDisabled(int index, AppAccessContext? effectiveAccess) {
    final item = _primaryItems[index];
    return _isRouteDisabled(
          item.route,
          feature: item.feature,
          accessContext: effectiveAccess,
        ) ||
        (subscriptionLimited && !limitedAllowedIndexes.contains(index));
  }

  bool _isRouteDisabled(
    String? route, {
    AppFeature? feature,
    AppAccessContext? accessContext,
  }) {
    if (route != null &&
        subscriptionLimited &&
        !limitedAllowedRoutes.contains(route)) {
      return true;
    }
    if (accessContext == null) return false;
    return !accessContext.canUse(feature ?? _featureForRoute(route));
  }

  AppFeature _featureForRoute(String? route) {
    if (route == null) return AppFeature.appShell;
    final primary = _primaryItems.where((item) => item.route == route).toList();
    if (primary.isNotEmpty) return primary.first.feature;
    final more = _moreItems.where((item) => item.route == route).toList();
    if (more.isNotEmpty) return more.first.feature;
    if (route.startsWith('/settings')) return AppFeature.appShell;
    return AppFeature.appShell;
  }

  AppAccessContext? _readAccess(
    BuildContext context, {
    bool listen = false,
  }) {
    if (access != null) return access;
    try {
      return Provider.of<AppAccessContext>(context, listen: listen);
    } catch (_) {
      return null;
    }
  }

  void _showLimitedNotice(
    BuildContext context, [
    AppFeature? feature,
    AppAccessContext? effectiveAccess,
  ]) {
    final accessContext = effectiveAccess ?? _readAccess(context);
    final message = feature != null && accessContext != null
        ? accessContext.unavailableMessageFor(feature)
        : limitedNotice ??
            'This church subscription is not active. Please contact your church admin about subscription options.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}

class _MoreMenuSheet extends StatelessWidget {
  final List<_MenuItem> items;
  final String? currentRoute;
  final bool subscriptionLimited;
  final Set<String> limitedAllowedRoutes;
  final String? limitedNotice;
  final AppAccessContext? access;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback onLogOut;

  const _MoreMenuSheet({
    required this.items,
    required this.currentRoute,
    required this.subscriptionLimited,
    required this.limitedAllowedRoutes,
    this.limitedNotice,
    this.access,
    required this.onSelectRoute,
    required this.onLogOut,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'More',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              _MoreMenuTile(
                item: item,
                isActive: item.route == currentRoute ||
                    (item.route == '/settings' &&
                        currentRoute?.startsWith('/settings') == true),
                isDisabled: _isDisabled(item),
                limitedNotice: item.route == null
                    ? limitedNotice
                    : access?.unavailableMessageFor(item.feature) ??
                        limitedNotice,
                onTap: () {
                  final route = item.route;
                  if (route != null) onSelectRoute(route);
                },
              ),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Log Out',
                style:
                    TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: onLogOut,
            ),
          ],
        ),
      ),
    );
  }

  bool _isDisabled(_MenuItem item) {
    final route = item.route;
    if (route != null &&
        subscriptionLimited &&
        !limitedAllowedRoutes.contains(route)) {
      return true;
    }
    final accessContext = access;
    if (accessContext == null) return false;
    return !accessContext.canUse(item.feature);
  }
}

class _MoreMenuTile extends StatelessWidget {
  final _MenuItem item;
  final bool isActive;
  final bool isDisabled;
  final String? limitedNotice;
  final VoidCallback onTap;

  const _MoreMenuTile({
    required this.item,
    required this.isActive,
    required this.isDisabled,
    this.limitedNotice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGraceRooms = item.route == '/grace_rooms';
    final activeColor =
        isGraceRooms ? theme.colorScheme.secondary : theme.colorScheme.primary;
    final iconColor = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
        : isActive || isGraceRooms
            ? activeColor
            : null;

    return ListTile(
      leading: isGraceRooms
          ? Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDisabled
                    ? theme.colorScheme.surfaceContainerHighest
                    : activeColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDisabled
                      ? theme.dividerColor.withValues(alpha: 0.12)
                      : activeColor.withValues(alpha: 0.32),
                ),
              ),
              child: Icon(
                isActive ? item.selectedIcon : item.icon,
                color: iconColor,
              ),
            )
          : Icon(
              isActive ? item.selectedIcon : item.icon,
              color: iconColor,
            ),
      title: Text(
        item.label,
        style: TextStyle(
          color: isDisabled
              ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
              : isActive
                  ? activeColor
                  : null,
          fontWeight:
              isActive || isGraceRooms ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      trailing: isDisabled ? const Icon(Icons.lock_outline) : null,
      selected: isActive,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabled: true,
      onTap: isDisabled
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    limitedNotice ??
                        'This church subscription is not active. Please contact your church admin about subscription options.',
                  ),
                ),
              );
            }
          : onTap,
    );
  }
}

class _MenuItem {
  final String label;
  final String? route;
  final IconData icon;
  final IconData selectedIcon;
  final AppFeature feature;

  const _MenuItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.feature,
    this.route,
  });
}
