import 'package:flutter/material.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/action_card.dart';

class MinistryDashboard extends StatelessWidget {
  final bool isLeader;
  const MinistryDashboard({super.key, this.isLeader = false});

  @override
  Widget build(BuildContext context) {
    return DashboardScaffold(
      title: isLeader ? 'Ministry Leader Dashboard' : 'Ministry Dashboard',
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Ministry statistics coming soon.'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Actions', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (isLeader)
          ActionCard(
            title: 'Team Roster',
            description: 'Manage volunteers and schedules',
            icon: Icons.supervisor_account,
            onTap: () {},
          )
        else
          ActionCard(
            title: 'My Tasks',
            description: 'View assigned duties',
            icon: Icons.checklist,
            onTap: () {},
          ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Upcoming Events',
          description: 'View ministry calendar',
          icon: Icons.calendar_month,
          onTap: () => Navigator.pushNamed(context, '/events'),
        ),
      ],
    );
  }
}
