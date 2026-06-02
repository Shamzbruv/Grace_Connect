class ChurchStats {
  final int attendanceThisWeek;
  final int attendanceLastWeek;
  final int activeMembers;
  final int sundaySchoolAdults;
  final int sundaySchoolYouth;
  final int sundaySchoolKids;
  final int ministryCount;
  final List<double> weeklyTrend;

  const ChurchStats({
    required this.attendanceThisWeek,
    required this.attendanceLastWeek,
    required this.activeMembers,
    required this.sundaySchoolAdults,
    required this.sundaySchoolYouth,
    required this.sundaySchoolKids,
    required this.ministryCount,
    required this.weeklyTrend,
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
