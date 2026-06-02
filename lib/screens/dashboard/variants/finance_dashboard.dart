import 'package:flutter/material.dart';
import '../widgets/dashboard_scaffold.dart';
import '../widgets/action_card.dart';

class FinanceDashboard extends StatelessWidget {
  const FinanceDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardScaffold(
      title: 'Finance Dashboard',
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Financial data coming soon.'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Tasks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        ActionCard(
          title: 'Record Contribution',
          description: 'Enter offline giving manually',
          icon: Icons.add_card,
          onTap: () {}, // Navigate to input
        ),
        const SizedBox(height: 12),
        ActionCard(
          title: 'View Financial Reports',
          description: 'Analyze giving trends',
          icon: Icons.bar_chart,
          onTap: () {},
        ),
      ],
    );
  }
}
