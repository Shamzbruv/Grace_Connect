import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/user_profile.dart';
import '../../../models/church_stats.dart';
import 'package:grace_connect/widgets/ui/app_card.dart'; // Assuming this exists based on read file
import '../dashboard_module.dart';

class ChurchHealthModule extends DashboardModule {
  final ChurchStats stats;
  const ChurchHealthModule({super.key, required this.stats});

  @override
  int get priority => 10; // secondary

  @override
  bool shouldShow(UserProfile user) {
    // Show to Pastors, Admins, etc.
    return user.isPastor || user.isAdmin || user.isAssistantPastor;
  }

  @override
  Widget build(BuildContext context) {
    // Reusing the logic from the old dashboard here
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text("Church Health",
              style: Theme.of(context).textTheme.titleLarge),
        ),
        _buildAttendanceChart(context, stats),
        // Add other widgets...
      ],
    );
  }

  Widget _buildAttendanceChart(BuildContext context, ChurchStats stats) {
    // Simplified chart
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: SizedBox(
        height: 150,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: stats.weeklyTrend.asMap().entries.map((e) {
                  return FlSpot(e.key.toDouble(), e.value);
                }).toList(),
                isCurved: true,
                color: Colors.indigo,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
