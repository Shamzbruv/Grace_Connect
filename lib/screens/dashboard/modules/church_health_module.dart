import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../models/user_profile.dart';
import '../../../models/church_stats.dart';
import '../../../theme/chart_palette.dart';
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
    final theme = Theme.of(context);
    final trend = stats.weeklyTrend;
    final labels = stats.weeklyTrendLabels;

    if (trend.isEmpty || trend.every((value) => value == 0)) {
      return AppCard(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 150,
          child: Center(
            child: Text(
              'Weekly attendance will appear here once services are finalized.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final color = ChartPalette.present(theme.brightness);
    final axisColor = ChartPalette.axis(theme.brightness);
    final maxY = trend.reduce((a, b) => a > b ? a : b);
    final yInterval = (maxY / 4).clamp(1, double.infinity).roundToDouble();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 12),
            child: Text(
              'Weekly attendance',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: FlGridData(
                  horizontalInterval: yInterval,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: axisColor, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: yInterval,
                      reservedSize: 32,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (trend.length / 4).clamp(1, double.infinity),
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(bottom: BorderSide(color: axisColor)),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: theme.colorScheme.inverseSurface,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final index = spot.x.toInt();
                      final label =
                          index >= 0 && index < labels.length ? labels[index] : '';
                      return LineTooltipItem(
                        '$label\n${spot.y.toInt()} attended',
                        TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: trend.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value);
                    }).toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
