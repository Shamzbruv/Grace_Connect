enum AppPermission {
  // Admin / Operational
  approveMembers,
  manageChurchSettings,
  manageRoles,
  viewOperationalAnalytics,

  // Finance
  viewFinanceDashboard,
  manageFinances, // enter/edit records
  approveFinanceReports,
  manageChurchSubscription,

  // Content / Community
  createAnnouncement,
  sendPushNotification,
  pinPost,
  moderateCommunity,
  createEvents,

  // Ministry Specific
  manageSundaySchool,
  manageLivestream,
  manageWorship,
  managePrayerRequests,
  assignCareRequests,
  manualCheckIn,

  // Attendance & Insights
  viewAttendanceInsights,
  viewPriorityList,
  managePriorityList, // Pastor only (resolve/remove)
  manageSchedule, // Secretary
}

class RBACConfig {
  static const Map<String, List<AppPermission>> rolePermissions = {
    'pastor': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.viewFinanceDashboard,
      AppPermission.approveFinanceReports,
      AppPermission.manageChurchSubscription,
      AppPermission.createAnnouncement,
      AppPermission.sendPushNotification,
      AppPermission.moderateCommunity,
      AppPermission.managePrayerRequests,
      AppPermission.assignCareRequests,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.managePriorityList,
      AppPermission.manageSchedule,
    ],
    'senior_pastor': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.viewFinanceDashboard,
      AppPermission.approveFinanceReports,
      AppPermission.manageChurchSubscription,
      AppPermission.createAnnouncement,
      AppPermission.sendPushNotification,
      AppPermission.moderateCommunity,
      AppPermission.managePrayerRequests,
      AppPermission.assignCareRequests,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.managePriorityList,
      AppPermission.manageSchedule,
    ],
    'assistant_pastor': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.manageChurchSubscription,
      AppPermission.createAnnouncement,
      AppPermission.createEvents,
      AppPermission.moderateCommunity,
      AppPermission.managePrayerRequests,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.manageSchedule,
    ],
    'acting_pastor': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.manageChurchSubscription,
      AppPermission.createAnnouncement,
      AppPermission.createEvents,
      AppPermission.moderateCommunity,
      AppPermission.managePrayerRequests,
      AppPermission.assignCareRequests,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.manageSchedule,
    ],
    'admin': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.moderateCommunity,
      AppPermission.createEvents,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.manageSchedule,
      AppPermission.manageChurchSubscription,
    ],
    'church_admin': [
      AppPermission.approveMembers,
      AppPermission.manageChurchSettings,
      AppPermission.manageRoles,
      AppPermission.viewOperationalAnalytics,
      AppPermission.moderateCommunity,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
      AppPermission.manageSchedule,
      AppPermission.manageChurchSubscription,
    ],
    'secretary': [
      AppPermission.createAnnouncement,
      AppPermission.createEvents,
      AppPermission.sendPushNotification,
      AppPermission.pinPost,
      AppPermission.manageSchedule,
    ],
    'church_secretary': [
      AppPermission.createAnnouncement,
      AppPermission.createEvents,
      AppPermission.sendPushNotification,
      AppPermission.pinPost,
      AppPermission.manageSchedule,
      AppPermission.approveMembers,
    ],
    'treasurer': [
      AppPermission.viewFinanceDashboard,
      AppPermission.manageFinances,
      AppPermission.manageChurchSubscription,
    ],
    'financial_secretary': [
      AppPermission.viewFinanceDashboard,
      AppPermission.manageFinances,
      AppPermission.manageChurchSubscription,
    ],
    'finance': [
      AppPermission.viewFinanceDashboard,
      AppPermission.manageChurchSubscription,
    ],
    'finance_officer': [
      AppPermission.viewFinanceDashboard,
      AppPermission.manageChurchSubscription,
    ],
    'accountant': [
      AppPermission.viewFinanceDashboard,
      AppPermission.manageChurchSubscription,
    ],
    'administrator': [
      AppPermission.manageChurchSettings,
      AppPermission.manageChurchSubscription,
    ],
    'church_administrator': [
      AppPermission.manageChurchSettings,
      AppPermission.manageChurchSubscription,
    ],
    'sunday_school_lead': [
      AppPermission.manageSundaySchool,
      AppPermission.createAnnouncement, // for class announcements
    ],
    'sunday_school_superintendent': [
      AppPermission.manageSundaySchool,
      AppPermission.createAnnouncement,
      AppPermission.createEvents,
    ],
    'sunday_school_teacher': [
      AppPermission.manageSundaySchool,
    ],
    'worship_leader': [
      AppPermission.manageWorship,
      AppPermission.createAnnouncement, // for rehearsal
    ],
    'media_team': [
      AppPermission.manageLivestream,
      AppPermission.pinPost, // on service days
    ],
    'media_av_director': [
      AppPermission.manageLivestream,
      AppPermission.pinPost,
      AppPermission.manageSchedule,
    ],
    'media_team_member': [
      AppPermission.manageLivestream,
    ],
    'deacon': [
      AppPermission.managePrayerRequests,
      AppPermission.moderateCommunity,
      AppPermission.viewAttendanceInsights,
      AppPermission.viewPriorityList,
    ],
    'usher': [
      AppPermission.manualCheckIn,
    ],
    'head_usher': [
      AppPermission.manualCheckIn,
      AppPermission.manageSchedule,
    ],
    'prayer_ministry_leader': [
      AppPermission.managePrayerRequests,
      AppPermission.createAnnouncement,
      AppPermission.assignCareRequests,
    ],
    'intercessor': [
      AppPermission.managePrayerRequests,
    ],
    'member': [], // Basic access only
  };

  static List<AppPermission> getPermissionsForRoles(List<String> roles) {
    final Set<AppPermission> permissions = {};
    for (final role in roles) {
      final normalizedRole = _normalizeRole(role);
      final rolePerms = rolePermissions[normalizedRole] ?? [];
      permissions.addAll(rolePerms);
    }
    return permissions.toList();
  }

  static String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
