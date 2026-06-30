import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/developer_service.dart';
import '../../services/ministry_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';

class SettingsHomeScreen extends StatelessWidget {
  const SettingsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roleProvider = Provider.of<UserRoleProvider>(context);
    final capabilities = roleProvider.userProfile?.capabilities;
    final bool isStaff = capabilities?.canManageMembersBasic == true ||
        capabilities?.canCreateEvents == true ||
        capabilities?.canManageSchedules == true;
    final roles = roleProvider.userProfile?.roles ?? const <String>[];
    final bool isFinance = capabilities?.canManageFinance == true ||
        roles.map(_normalizeRole).any({'pastor', 'senior_pastor'}.contains);
    final developerAccessFuture = DeveloperService().hasDeveloperAccess();
    final ministryAccessFuture = MinistryService().managesAnyMinistry();

    return AppScaffold(
      title: 'Settings',
      withBackground: true,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSectionHeader(context, 'General'),
            AppCard(
              child: Column(
                children: [
                  _buildSettingsTile(context, Icons.person_outline, 'Account',
                      'Profile, Password, Roles', '/settings/account'),
                  const Divider(height: 1),
                  _buildSettingsTile(
                      context,
                      Icons.lock_outline,
                      'Privacy & Safety',
                      'Visibility, Blocking',
                      '/settings/privacy'),
                  const Divider(height: 1),
                  _buildSettingsTile(
                      context,
                      Icons.notifications_outlined,
                      'Notifications',
                      'Push categories, DND',
                      '/settings/notifications'),
                  const Divider(height: 1),
                  _buildSettingsTile(
                      context,
                      Icons.devices_other,
                      'Devices & App',
                      'Theme, Data usage',
                      '/settings/app_config'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(context, 'Church Life'),
            AppCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                      context,
                      Icons.location_on_outlined,
                      'Attendance & Location',
                      'Auto-checkin, Geofence',
                      '/settings/attendance'),
                  const Divider(height: 1),
                  _buildSettingsTile(context, Icons.people_outline, 'Community',
                      'Comments, Moderation', '/settings/community'),
                  const Divider(height: 1),
                  _buildSettingsTile(
                      context,
                      Icons.book_outlined,
                      'Bible & Study',
                      'Plans, Study Partners',
                      '/settings/bible'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FutureBuilder<bool>(
              future: ministryAccessFuture,
              builder: (context, snapshot) {
                final hasMinistryAccess = snapshot.data ?? false;
                if (!isStaff && !hasMinistryAccess) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSectionHeader(context, 'Staff & Administration'),
                    AppCard(
                      child: Column(
                        children: [
                          if (isStaff) ...[
                            _buildSettingsTile(
                                context,
                                Icons.church_outlined,
                                'Church Settings',
                                'Profile, Schedules, Approval',
                                '/settings/church_admin'),
                            const Divider(height: 1),
                          ],
                          _buildSettingsTile(
                              context,
                              Icons.groups_outlined,
                              'Ministries',
                              'Ministry teams and managers',
                              '/ministries'),
                          if (isFinance) ...[
                            const Divider(height: 1),
                            _buildSettingsTile(
                                context,
                                Icons.volunteer_activism_outlined,
                                'Giving',
                                'SpurrOpen giving link',
                                '/settings/finance'),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            _buildSectionHeader(context, 'Support'),
            AppCard(
              child: Column(
                children: [
                  _buildSettingsTile(context, Icons.help_outline,
                      'Help & Support', 'Tickets, Contact', '/support'),
                  const Divider(height: 1),
                  _buildSettingsTile(context, Icons.bug_report_outlined,
                      'Beta Feedback', 'Report a bug', '/settings/feedback'),
                ],
              ),
            ),
            FutureBuilder<bool>(
              future: developerAccessFuture,
              builder: (context, snapshot) {
                final isDeveloper = snapshot.data == true;
                if (!isDeveloper) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    _buildSectionHeader(context, 'Developer'),
                    AppCard(
                      child: Column(
                        children: [
                          _buildSettingsTile(
                            context,
                            Icons.code,
                            'Developer Console',
                            'Platform tools, logs',
                            '/developer_console',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            Text('Version 1.0.15-beta',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isDarkMode ? Colors.white : AppColors.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title,
      String subtitle, String route) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: isDarkMode ? Colors.white : AppColors.primary, size: 20),
      ),
      title: Text(title,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: () => Navigator.pushNamed(context, route),
    );
  }

  String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
