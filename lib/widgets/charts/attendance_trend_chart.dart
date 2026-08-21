import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/attendance_analytics_service.dart';
import '../../theme/chart_palette.dart';

enum _AttendanceView { breakdown, rate, table }

/// Church-wide attendance analytics: a stacked breakdown (present/late/
/// remote/absent per service), a rate trend, and a plain accessible table --
/// all three views of the same [summaries], switchable so nobody is stuck
/// with only a chart they can't read.
class AttendanceTrendChart extends StatefulWidget {
  const AttendanceTrendChart({super.key, required this.summaries});

  final List<ServiceAttendanceSummary> summaries;

  @override
  State<AttendanceTrendChart> createState() => _AttendanceTrendChartState();
}

class _AttendanceTrendChartState extends State<AttendanceTrendChart> {
  _AttendanceView _view = _AttendanceView.breakdown;
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaries = widget.summaries;

    if (summaries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Attendance analytics appear here once a service has been finalized.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attendance Analytics',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            SegmentedButton<_AttendanceView>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: _AttendanceView.breakdown,
                  label: Text('Chart'),
                  icon: Icon(Icons.bar_chart, size: 16),
                ),
                ButtonSegment(
                  value: _AttendanceView.rate,
                  label: Text('Rate'),
                  icon: Icon(Icons.show_chart, size: 16),
                ),
                ButtonSegment(
                  value: _AttendanceView.table,
                  label: Text('Table'),
                  icon: Icon(Icons.table_rows_outlined, size: 16),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        switch (_view) {
          _AttendanceView.breakdown => _buildBreakdownChart(theme, summaries),
          _AttendanceView.rate => _buildRateChart(theme, summaries),
          _AttendanceView.table => _buildTable(theme, summaries),
        },
      ],
    );
  }

  Widget _buildLegend(ThemeData theme) {
    final brightness = theme.brightness;
    final entries = <(String, Color)>[
      ('Present', ChartPalette.present(brightness)),
      ('Late', ChartPalette.late(brightness)),
      ('Remote', ChartPalette.remote(brightness)),
      ('Absent', ChartPalette.absent(brightness)),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final entry in entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: entry.$2, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(entry.$1, style: theme.textTheme.bodySmall),
            ],
          ),
      ],
    );
  }

  Widget _buildBreakdownChart(
    ThemeData theme,
    List<ServiceAttendanceSummary> summaries,
  ) {
    final brightness = theme.brightness;
    final axisColor = ChartPalette.axis(brightness);
    final maxExpected = summaries
        .map((s) => s.expectedCount)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();
    final maxY = maxExpected <= 0 ? 5.0 : maxExpected * 1.15;
    // Bars need real horizontal room per service (labels, gap between
    // fills) -- scrolling a wide chart beats squeezing a dozen services
    // into an unreadable smear.
    final chartWidth = (summaries.length * 56.0).clamp(
      MediaQuery.of(context).size.width - 32,
      double.infinity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLegend(theme),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  minY: 0,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: axisColor, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border(bottom: BorderSide(color: axisColor)),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) => Text(
                          value.toInt().toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= summaries.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('M/d').format(
                                summaries[index].serviceDate,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response?.spot == null) {
                        setState(() => _touchedIndex = null);
                        return;
                      }
                      setState(() =>
                          _touchedIndex = response!.spot!.touchedBarGroupIndex);
                    },
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: theme.colorScheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final summary = summaries[groupIndex];
                        return BarTooltipItem(
                          '${summary.serviceName}\n'
                          '${DateFormat('MMM d, yyyy').format(summary.serviceDate)}\n'
                          'Present ${summary.presentCount} · Late ${summary.lateCount}\n'
                          'Remote ${summary.remoteCount} · Absent ${summary.absentCount}',
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (final entry in summaries.asMap().entries)
                      _stackedGroup(
                        entry.key,
                        entry.value,
                        brightness,
                        highlighted: _touchedIndex == entry.key,
                        gapColor: theme.scaffoldBackgroundColor,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  BarChartGroupData _stackedGroup(
    int index,
    ServiceAttendanceSummary summary,
    Brightness brightness, {
    required bool highlighted,
    required Color gapColor,
  }) {
    final segments = <(int, Color)>[
      (summary.presentCount, ChartPalette.present(brightness)),
      (summary.lateCount, ChartPalette.late(brightness)),
      (summary.remoteCount, ChartPalette.remote(brightness)),
      (summary.absentCount, ChartPalette.absent(brightness)),
    ];
    var runningTotal = 0.0;
    final stackItems = <BarChartRodStackItem>[];
    for (final (count, color) in segments) {
      if (count <= 0) continue;
      final from = runningTotal;
      runningTotal += count;
      // A surface-colored stroke around each segment stands in for the
      // dataviz mark spec's gap between stacked fills. Insetting fromY
      // instead (as this used to) shrinks that segment's rendered height
      // below its true value -- a count of 1 drew as if it were 0.6,
      // understating small segments by up to 40%. A border draws on top of
      // the true from/to edges, so every segment keeps its exact height.
      stackItems.add(BarChartRodStackItem(
        from,
        runningTotal,
        color,
        BorderSide(color: gapColor, width: 1.5),
      ));
    }

    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: runningTotal,
          width: 22,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          rodStackItems: stackItems,
          color: Colors.transparent,
          backDrawRodData: BackgroundBarChartRodData(show: false),
        ),
      ],
      showingTooltipIndicators: highlighted ? [0] : [],
    );
  }

  Widget _buildRateChart(
    ThemeData theme,
    List<ServiceAttendanceSummary> summaries,
  ) {
    final rated = summaries
        .asMap()
        .entries
        .where((e) => e.value.attendanceRate != null)
        .toList();
    if (rated.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No services with a known roster size yet.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final color = ChartPalette.present(theme.brightness);
    final axisColor = ChartPalette.axis(theme.brightness);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: FlGridData(
            horizontalInterval: 25,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: axisColor, strokeWidth: 1),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(bottom: BorderSide(color: axisColor)),
          ),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 38,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}%',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= summaries.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('M/d').format(summaries[index].serviceDate),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: theme.colorScheme.inverseSurface,
              getTooltipItems: (spots) => spots.map((spot) {
                final index = spot.x.toInt();
                final name = index >= 0 && index < summaries.length
                    ? summaries[index].serviceName
                    : '';
                return LineTooltipItem(
                  '$name\n${spot.y.toStringAsFixed(0)}% attended',
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
              spots: [
                for (final entry in rated)
                  FlSpot(entry.key.toDouble(), entry.value.attendanceRate!),
              ],
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
    );
  }

  Widget _buildTable(
    ThemeData theme,
    List<ServiceAttendanceSummary> summaries,
  ) {
    final brightness = theme.brightness;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: const [
          DataColumn(label: Text('Service')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Present'), numeric: true),
          DataColumn(label: Text('Late'), numeric: true),
          DataColumn(label: Text('Remote'), numeric: true),
          DataColumn(label: Text('Absent'), numeric: true),
          DataColumn(label: Text('Rate'), numeric: true),
        ],
        rows: [
          for (final summary in summaries.reversed)
            DataRow(cells: [
              DataCell(Text(summary.serviceName)),
              DataCell(
                  Text(DateFormat('MMM d, yyyy').format(summary.serviceDate))),
              DataCell(_countCell(
                  summary.presentCount, ChartPalette.present(brightness))),
              DataCell(_countCell(
                  summary.lateCount, ChartPalette.late(brightness))),
              DataCell(_countCell(
                  summary.remoteCount, ChartPalette.remote(brightness))),
              DataCell(_countCell(
                  summary.absentCount, ChartPalette.absent(brightness))),
              DataCell(Text(summary.attendanceRate == null
                  ? '—'
                  : '${summary.attendanceRate!.toStringAsFixed(0)}%')),
            ]),
        ],
      ),
    );
  }

  Widget _countCell(int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$value'),
      ],
    );
  }
}
