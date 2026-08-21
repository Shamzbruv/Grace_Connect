import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/church_stats.dart';
import 'package:grace_connect/models/user_profile.dart';
import 'package:grace_connect/screens/dashboard/modules/church_health_module.dart';

UserProfile _pastorProfile() {
  return UserProfile.fromMap({
    'uid': 'pastor-1',
    'fullName': 'Test Pastor',
    'roles': ['Pastor'],
  });
}

void main() {
  testWidgets('shows a graceful message instead of a fake chart with no real data',
      (tester) async {
    const stats = ChurchStats(
      attendanceThisWeek: 0,
      attendanceLastWeek: 0,
      activeMembers: 0,
      sundaySchoolAdults: 0,
      sundaySchoolYouth: 0,
      sundaySchoolKids: 0,
      ministryCount: 0,
      weeklyTrend: [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChurchHealthModule(stats: stats)),
      ),
    );

    expect(
      find.textContaining('will appear here once services are finalized'),
      findsOneWidget,
    );
    // The old stub padded three fake zeros in front of real data -- there
    // must be no chart drawn at all when every point is a placeholder zero.
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('renders a labeled line chart from real weekly totals',
      (tester) async {
    const stats = ChurchStats(
      attendanceThisWeek: 42,
      attendanceLastWeek: 38,
      activeMembers: 60,
      sundaySchoolAdults: 0,
      sundaySchoolYouth: 0,
      sundaySchoolKids: 0,
      ministryCount: 3,
      weeklyTrend: [30, 34, 38, 42],
      weeklyTrendLabels: ['Jul 6', 'Jul 13', 'Jul 20', 'Jul 27'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChurchHealthModule(stats: stats)),
      ),
    );

    expect(find.text('Weekly attendance'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    // A real week label must be visible on the axis, not a bare index.
    expect(find.text('Jul 6'), findsOneWidget);
  });

  test('shouldShow gates the module to leadership roles', () {
    final module = ChurchHealthModule(
      stats: const ChurchStats(
        attendanceThisWeek: 0,
        attendanceLastWeek: 0,
        activeMembers: 0,
        sundaySchoolAdults: 0,
        sundaySchoolYouth: 0,
        sundaySchoolKids: 0,
        ministryCount: 0,
        weeklyTrend: [],
      ),
    );
    expect(module.shouldShow(_pastorProfile()), isTrue);
  });
}
