import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/attendance_analytics_service.dart';
import 'package:grace_connect/widgets/charts/attendance_trend_chart.dart';

ServiceAttendanceSummary _summary({
  required String id,
  required DateTime date,
  int present = 0,
  int late = 0,
  int remote = 0,
  int absent = 0,
}) {
  return ServiceAttendanceSummary.fromMap({
    'service_id': id,
    'service_name': 'Sunday Service',
    'service_date': date.toIso8601String(),
    'present_count': present,
    'late_count': late,
    'remote_count': remote,
    'absent_count': absent,
  });
}

void main() {
  group('ServiceAttendanceSummary', () {
    test('attendance rate is the attended share of the expected roster', () {
      final summary = _summary(
        id: '1',
        date: DateTime(2026, 8, 2),
        present: 6,
        late: 2,
        remote: 1,
        absent: 1,
      );
      expect(summary.attendedCount, 9);
      expect(summary.expectedCount, 10);
      expect(summary.attendanceRate, 90.0);
    });

    test('rate is null (not a misleading 0%) when nobody was expected', () {
      final summary = _summary(id: '1', date: DateTime(2026, 8, 2));
      expect(summary.attendanceRate, isNull);
    });
  });

  group('AttendanceTrendChart', () {
    testWidgets('shows a graceful empty state with no summaries',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AttendanceTrendChart(summaries: []),
          ),
        ),
      );

      expect(
        find.textContaining('appear here once a service has been finalized'),
        findsOneWidget,
      );
      // The empty state must not attempt to render a chart against no data.
      expect(find.byType(SegmentedButton<Object>), findsNothing);
    });

    testWidgets('renders the breakdown chart by default and switches views',
        (tester) async {
      final summaries = [
        _summary(
          id: '1',
          date: DateTime(2026, 8, 2),
          present: 5,
          late: 1,
          remote: 1,
          absent: 2,
        ),
        _summary(
          id: '2',
          date: DateTime(2026, 8, 9),
          present: 7,
          late: 0,
          remote: 0,
          absent: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceTrendChart(summaries: summaries),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Attendance Analytics'), findsOneWidget);
      // Legend for the four-outcome breakdown must always be present.
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Late'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Absent'), findsOneWidget);

      // Switch to the accessible table view -- required whenever a
      // categorical palette carries a contrast WARN (dataviz skill).
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('Sunday Service'), findsWidgets);

      // The table view's own "Rate" column header collides with the segment
      // label once the table is showing -- the segment control is earlier
      // in the tree.
      await tester.tap(find.text('Rate').first);
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    });
  });
}
