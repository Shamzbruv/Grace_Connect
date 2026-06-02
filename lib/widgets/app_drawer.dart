import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/user_role_provider.dart';
import '../models/user_profile.dart'; // Import UserProfile
import '../theme/app_colors.dart';

class AppDrawer extends StatelessWidget {
  final UserProfile? userProfile;
  const AppDrawer({super.key, this.userProfile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = Provider.of<UserRoleProvider>(context);
    final userProfile = userProvider.userProfile;

    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Modern Profile Header
            _buildModernHeader(context, userProfile, theme),

            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSectionHeader(context, 'MENU'),
                  _buildDrawerItem(context, Icons.home_outlined, 'Member View',
                      '/member_view'),
                  _buildDrawerItem(context, Icons.dashboard_outlined,
                      'Dashboard', '/admin_dashboard'),
                  _buildDrawerItem(
                      context, Icons.people_outline, 'Members', '/members'),
                  _buildDrawerItem(context, Icons.calendar_month_outlined,
                      'Events', '/events'),
                  _buildDrawerItem(context, Icons.diversity_3_outlined,
                      'Community', '/community'),
                  _buildDrawerItem(context, Icons.auto_awesome_outlined,
                      'Testimonies', '/testimonies'),
                  _buildDrawerItem(
                      context, Icons.menu_book_outlined, 'Bible', '/bible'),

                  // NEW TABS
                  _buildDrawerItem(context, Icons.checklist_rtl_outlined,
                      'Attendance', '/attendance'),
                  _buildDrawerItem(context, Icons.volunteer_activism_outlined,
                      'Prayers', '/prayers'),
                  _buildDrawerItem(context, Icons.favorite_outline,
                      'Counseling', '/counseling'),
                  _buildDrawerItem(context, Icons.live_tv_outlined,
                      'Live Streaming', '/live_streaming'),
                  _buildDrawerItem(context, Icons.analytics_outlined,
                      'Analytics', '/analytics'),

                  const Divider(height: 32),

                  _buildSectionHeader(context, 'FINANCE'),
                  _buildDrawerItem(context, Icons.volunteer_activism_outlined,
                      'Giving', '/donations'),

                  const Divider(height: 32),

                  _buildSectionHeader(context, 'SETTINGS'),
                  _buildDrawerItem(context, Icons.settings_outlined, 'Settings',
                      '/settings'),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextButton.icon(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    // FIX: Navigation Back Stack Bug
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Log Out',
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.centerLeft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernHeader(
      BuildContext context, UserProfile? profile, ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // Close drawer
        Navigator.pushNamed(context, '/profile');
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor, // Seamless with drawer bg
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.gold,
              backgroundImage: (profile?.photoUrl.isNotEmpty == true)
                  ? NetworkImage(profile!.photoUrl)
                  : ((Supabase.instance.client.auth.currentUser
                              ?.userMetadata?['avatar_url']?.isNotEmpty ==
                          true)
                      ? NetworkImage(Supabase.instance.client.auth.currentUser!
                          .userMetadata!['avatar_url']!)
                      : null),
              child: ((profile?.photoUrl.isEmpty ?? true) &&
                      (Supabase.instance.client.auth.currentUser
                              ?.userMetadata?['avatar_url']?.isEmpty ??
                          true))
                  ? Text(
                      (profile?.fullName.isNotEmpty == true)
                          ? profile!.fullName[0].toUpperCase()
                          : (Supabase
                                      .instance
                                      .client
                                      .auth
                                      .currentUser
                                      ?.userMetadata?['full_name']
                                      ?.isNotEmpty ==
                                  true
                              ? Supabase.instance.client.auth.currentUser!
                                  .userMetadata!['full_name'][0]
                                  .toUpperCase()
                              : 'U'),
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 24),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (profile?.fullName.isNotEmpty == true)
                        ? profile!.fullName
                        : (Supabase.instance.client.auth.currentUser
                                ?.userMetadata?['full_name'] ??
                            'Guest User'),
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (profile != null && profile.roles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          profile.roles.first.toUpperCase(),
                          style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).hintColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDrawerItem(
      BuildContext context, IconData icon, String title, String route) {
    final theme = Theme.of(context);
    final isActive = ModalRoute.of(context)?.settings.name == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? theme.colorScheme.primary : theme.iconTheme.color,
          size: 22,
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive
                ? theme.colorScheme.primary
                : theme.textTheme.bodyMedium?.color,
            fontSize: 15,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        dense: true,
        horizontalTitleGap: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () {
          Navigator.pop(context); // Close drawer
          if (!isActive) {
            Navigator.pushNamed(context, route);
          }
        },
      ),
    );
  }
}
