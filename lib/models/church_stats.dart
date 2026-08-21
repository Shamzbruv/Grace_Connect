class ChurchStats {
  final int attendanceThisWeek;
  final int attendanceLastWeek;
  final int activeMembers;
  final int sundaySchoolAdults;
  final int sundaySchoolYouth;
  final int sundaySchoolKids;
  final int ministryCount;
  final List<double> weeklyTrend;
  // Short label (e.g. "Aug 3") per weeklyTrend point, same length and order.
  // A trend line with no axis labels is unreadable as anything but a vague
  // shape -- this is what lets the chart actually say which week is which.
  final List<String> weeklyTrendLabels;

  const ChurchStats({
    required this.attendanceThisWeek,
    required this.attendanceLastWeek,
    required this.activeMembers,
    required this.sundaySchoolAdults,
    required this.sundaySchoolYouth,
    required this.sundaySchoolKids,
    required this.ministryCount,
    required this.weeklyTrend,
    this.weeklyTrendLabels = const [],
  });

  factory ChurchStats.fromMap(Map<String, dynamic> data) {
    return ChurchStats(
      attendanceThisWeek: data['attendanceThisWeek'] ?? 0,
      attendanceLastWeek: data['attendanceLastWeek'] ?? 0,
      activeMembers: data['activeMembers'] ?? 0,
      sundaySchoolAdults: data['sundaySchoolAdults'] ?? 0,
      sundaySchoolYouth: data['sundaySchoolYouth'] ?? 0,
      sundaySchoolKids: data['sundaySchoolKids'] ?? 0,
      ministryCount: data['ministryCount'] ?? 0,
      weeklyTrend: List<double>.from(
          (data['weeklyTrend'] ?? []).map((x) => x.toDouble())),
      weeklyTrendLabels: List<String>.from(
          (data['weeklyTrendLabels'] ?? []).map((x) => x.toString())),
    );
  }

  // Empty initial data
  factory ChurchStats.empty() {
    return const ChurchStats(
      attendanceThisWeek: 0,
      attendanceLastWeek: 0,
      activeMembers: 0,
      sundaySchoolAdults: 0,
      sundaySchoolYouth: 0,
      sundaySchoolKids: 0,
      ministryCount: 0,
      weeklyTrend: [],
    );
  }
}
