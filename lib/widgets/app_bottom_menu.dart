import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../providers/user_role_provider.dart';
import '../services/feed_scroll_service.dart';

class AppBottomMenu extends StatelessWidget {
  const AppBottomMenu({
    super.key,
    this.selectedIndex,
    this.onDestinationSelected,
  });

  final int? selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  static const List<_MenuItem> _primaryItems = [
    _MenuItem(
      label: 'Feed',
      route: '/community',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
    ),
    _MenuItem(
      label: 'Events',
      route: '/events',
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
    ),
    _MenuItem(
      label: 'Home',
      route: '/dashboard',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    _MenuItem(
      label: 'Bible',
      route: '/bible',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
    ),
    _MenuItem(
      label: 'More',
      icon: Icons.more_horiz,
      selectedIcon: Icons.more,
    ),
  ];

  static const List<_MenuItem> _moreItems = [
    _MenuItem(
      label: 'Members',
      route: '/members',
      icon: Icons.people_outline,
      selectedIcon: Icons.people,
    ),
    _MenuItem(
      label: 'Announcements',
      route: '/announcements',
      icon: Icons.campaign_outlined,
      selectedIcon: Icons.campaign,
    ),
    _MenuItem(
      label: 'Ministries',
      route: '/ministries',
      icon: Icons.groups_outlined,
      selectedIcon: Icons.groups,
    ),
    _MenuItem(
      label: 'Attendance',
      route: '/attendance',
      icon: Icons.checklist_rtl_outlined,
      selectedIcon: Icons.checklist_rtl,
    ),
    _MenuItem(
      label: 'Transfer',
      route: '/church_transfer',
      icon: Icons.compare_arrows_outlined,
      selectedIcon: Icons.compare_arrows,
    ),
    _MenuItem(
      label: 'Prayers',
      route: '/prayers',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism,
    ),
    _MenuItem(
      label: 'Counseling',
      route: '/counseling',
      icon: Icons.favorite_outline,
      selectedIcon: Icons.favorite,
    ),
    _MenuItem(
      label: 'Live Streaming',
      route: '/live_streaming',
      icon: Icons.live_tv_outlined,
      selectedIcon: Icons.live_tv,
    ),
    _MenuItem(
      label: 'Analytics',
      route: '/analytics',
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
    ),
    _MenuItem(
      label: 'Notifications',
      route: '/notifications',
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
    ),
    _MenuItem(
      label: 'Giving',
      route: '/donations',
      icon: Icons.volunteer_activism_outlined,
      selectedIcon: Icons.volunteer_activism,
    ),
    _MenuItem(
      label: 'Settings',
      route: '/settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
    ),
    _MenuItem(
      label: 'Profile',
      route: '/profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
    _MenuItem(
      label: 'Support',
      route: '/support',
      icon: Icons.support_agent_outlined,
      selectedIcon: Icons.support_agent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveSelectedIndex = selectedIndex ?? _selectedIndex(context);

    return NavigationBar(
      selectedIndex: effectiveSelectedIndex,
      height: 72,
      backgroundColor: theme.colorScheme.surface,
      indicatorColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.75),
      elevation: 6,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        final controlledSelection = onDestinationSelected;
        if (controlledSelection != null) {
          controlledSelection(index);
          return;
        }

        final item = _primaryItems[index];
        final route = item.route;

        if (route == null) {
          _showMoreMenu(context);
          return;
        }

        _navigateTo(context, route);
      },
      destinations: [
        for (final item in _primaryItems)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label,
          ),
      ],
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

  void _navigateTo(BuildContext context, String route) {
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _MoreMenuSheet(
          items: items,
          currentRoute: currentRoute,
          onSelectRoute: (route) {
            Navigator.of(sheetContext).pop();
            _navigateTo(context, route);
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
      return true;
    }).toList(growable: false);
  }

  bool _canViewMembers(UserProfile? profile) {
    if (profile == null) return false;
    final capabilities = profile.capabilities;
    return profile.isDeveloper ||
        capabilities.canManageMembersBasic ||
        capabilities.canManageRoles;
  }

  bool _canViewAnalytics(UserProfile? profile) {
    if (profile == null) return false;
    final capabilities = profile.capabilities;
    return profile.isDeveloper ||
        capabilities.canManageMembersBasic ||
        capabilities.canViewFinance ||
        capabilities.canApproveHighImpactEvents;
  }
}

class _MoreMenuSheet extends StatelessWidget {
  final List<_MenuItem> items;
  final String? currentRoute;
  final ValueChanged<String> onSelectRoute;
  final VoidCallback onLogOut;

  const _MoreMenuSheet({
    required this.items,
    required this.currentRoute,
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
}

class _MoreMenuTile extends StatelessWidget {
  final _MenuItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _MoreMenuTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        isActive ? item.selectedIcon : item.icon,
        color: isActive ? theme.colorScheme.primary : null,
      ),
      title: Text(
        item.label,
        style: TextStyle(
          color: isActive ? theme.colorScheme.primary : null,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: isActive,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onTap: onTap,
    );
  }
}

class _MenuItem {
  final String label;
  final String? route;
  final IconData icon;
  final IconData selectedIcon;

  const _MenuItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.route,
  });
}
