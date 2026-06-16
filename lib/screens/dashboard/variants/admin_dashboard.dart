import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../theme/app_colors.dart';
import '../../../../providers/user_role_provider.dart';
import '../../../../services/church_stats_service.dart';
import '../../../../models/church_stats.dart';
import '../../admin/member_management_screen.dart';
import '../../admin/finance_dashboard_screen.dart';
import '../../admin/admin_stream_settings_screen.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/stat_card.dart';
import '../widgets/action_card.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userProfile = Provider.of<UserRoleProvider>(context).userProfile;
    final churchId = userProfile?.churchId;

    if (userProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!userProfile.capabilities.canManageMembersBasic) {
      return const Scaffold(
        body: Center(child: Text('You do not have access to admin tools.')),
      );
    }

    return DashboardScaffold(
      title: 'Admin Dashboard',
      children: [
        // Real Stats
        if (churchId != null)
          StreamBuilder<ChurchStats>(
              stream:
                  Stream.fromFuture(ChurchStatsService().getStats(churchId)),
              initialData: const ChurchStats(
                attendanceThisWeek: 0,
                attendanceLastWeek: 0,
                activeMembers: 0,
                sundaySchoolAdults: 0,
                sundaySchoolYouth: 0,
                sundaySchoolKids: 0,
                ministryCount: 0,
                weeklyTrend: [],
              ),
              builder: (context, snapshot) {
                final stats = snapshot.data!;
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: StatCard(
                          label: 'Members',
                          value: stats.activeMembers.toString(),
                          icon: Icons.people,
                          colorOverride: AppColors.secondary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(
                            child: StatCard(
                          label: 'Attendance',
                          value: stats.attendanceThisWeek.toString(),
                          icon: Icons.event_available,
                        )),
                      ],
                    ),
                    const SizedBox(height: 12),
                    StatCard(
                      label: 'Ministries',
                      value: stats.ministryCount.toString(),
                      icon: Icons.groups,
                      colorOverride: Colors.green,
                    ),
                  ],
                );
              }),

        const SizedBox(height: 24),

        Text('Quick Actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Member Management',
          description: 'Manage users and roles',
          icon: Icons.manage_accounts,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const MemberManagementScreen())),
        ),
        const SizedBox(height: 12),
        if (userProfile.canManageRoles)
          ActionCard(
            title: 'Role Assignments',
            description: 'Assign ministry and admin access',
            icon: Icons.security,
            onTap: () => Navigator.pushNamed(context, '/role_management'),
          ),
        if (userProfile.canManageRoles) const SizedBox(height: 12),
        if (userProfile.canManageRoles)
          ActionCard(
            title: 'Ministries',
            description: 'Create ministries and assign managers',
            icon: Icons.groups_outlined,
            onTap: () => Navigator.pushNamed(context, '/ministries'),
          ),
        if (userProfile.canManageRoles) const SizedBox(height: 12),
        if (userProfile.canViewFinance)
          ActionCard(
            title: 'Finance Overview',
            description: 'View donations and giving trends',
            icon: Icons.attach_money,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FinanceDashboardScreen(),
              ),
            ),
          ),
        if (userProfile.canViewFinance) const SizedBox(height: 12),
        ActionCard(
          title: 'Live Stream Settings',
          description: 'Manage YouTube URL and Go Live',
          icon: Icons.live_tv,
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const AdminStreamSettingsScreen())),
        ),
        const SizedBox(height: 12),
        if (userProfile.capabilities.canManageSchedules)
          ActionCard(
            title: 'Service Schedules',
            description: 'Create recurring services for attendance',
            icon: Icons.event_available_outlined,
            onTap: () => Navigator.pushNamed(context, '/schedule_management'),
          ),
        if (userProfile.capabilities.canManageSchedules)
          const SizedBox(height: 12),
        ActionCard(
          title: 'Attendance Alerts',
          description: 'Set absence alerts and coordinate care follow-up',
          icon: Icons.volunteer_activism_outlined,
          onTap: () => Navigator.pushNamed(context, '/attendance_insights'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Create Announcement',
          description: 'Send church-wide updates',
          icon: Icons.campaign_outlined,
          onTap: () => Navigator.pushNamed(context, '/announcements'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Prayer Requests',
          description: 'Review and respond to church prayer needs',
          icon: Icons.volunteer_activism,
          onTap: () => Navigator.pushNamed(context, '/prayers'),
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Counseling Cases',
          description: 'View care requests from members',
          icon: Icons.favorite,
          onTap: () => Navigator.pushNamed(context, '/counseling'),
        ),
      ],
    );
  }
}
