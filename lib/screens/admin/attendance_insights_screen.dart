import 'package:flutter/material.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../theme/app_colors.dart';

class AttendanceInsightsScreen extends StatefulWidget {
  const AttendanceInsightsScreen({super.key});

  @override
  State<AttendanceInsightsScreen> createState() =>
      _AttendanceInsightsScreenState();
}

class _AttendanceInsightsScreenState extends State<AttendanceInsightsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _atRiskMembers = [];

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    // In a real app, this would be a specialized query
    // For now, we mock the "Analysis" phase or fetch all and filter
    await Future.delayed(const Duration(seconds: 1)); // Simulate compute

    if (mounted) {
      setState(() {
        _atRiskMembers =
            []; // Replaced mock data with empty list until real data fetching is implemented
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Attendance Insights',
      showBottomMenu: true,
      body: _isLoading
          ? const Center(child: AppLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSummaryCard(),
                const SizedBox(height: 24),
                Text(
                  'At Risk Members',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Members absent for 2+ consecutive weeks',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                ..._atRiskMembers.map((member) => _buildMemberRiskCard(member)),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return AppCard(
      color: AppColors.primary,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Retention Rate',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                'N/A', // Replaced placeholder 94%
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Icon(Icons.show_chart, color: Colors.white54, size: 60),
        ],
      ),
    );
  }

  Widget _buildMemberRiskCard(Map<String, dynamic> member) {
    final int weeks = member['weeksAbsent'];
    final double riskLevel = (weeks / 4).clamp(0.0, 1.0); // 4 weeks is max risk

    Color riskColor = Colors.orange;
    String status = 'At Risk';

    if (weeks >= 4) {
      riskColor = Colors.red;
      status = 'Critical';
    } else if (weeks <= 2) {
      riskColor = Colors.amber;
      status = 'Warning';
    }

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: riskColor.withValues(alpha: 0.1),
                child: Text(member['name'][0],
                    style: TextStyle(
                        color: riskColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member['name'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      'Last seen: ${member['lastSeen']}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                      color: riskColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Risk Indicator / Lever
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Absence Duration',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Text(
                    '$weeks Weeks',
                    style: TextStyle(
                        color: riskColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: riskLevel,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
