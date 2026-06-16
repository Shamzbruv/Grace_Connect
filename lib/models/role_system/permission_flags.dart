class UserCapabilities {
  // --- EVENTS & CONTENT ---
  final bool canCreateEvents;
  final bool canEditEvents;
  final bool canPublishAnnouncements;
  final bool canModeratePosts;
  final bool canManageSchedules;

  // --- PRAYER & CARE ---
  final bool canAssignPrayers;
  final bool canViewSensitivePrayers;
  final bool canManageCareCases;
  final bool canViewAssignedCareCases;

  // --- MEMBER & ADMIN ---
  final bool canManageMembersBasic;
  final bool canManageRoles;
  final bool canViewFinance;
  final bool canManageFinance;

  // --- MEDIA & PRODUCTION ---
  final bool canManageMediaUploads;
  final bool canManageServiceChecklists;

  // --- LEADERSHIP ---
  final bool canApproveHighImpactEvents;

  const UserCapabilities({
    this.canCreateEvents = false,
    this.canEditEvents = false,
    this.canPublishAnnouncements = false,
    this.canModeratePosts = false,
    this.canManageSchedules = false,
    this.canAssignPrayers = false,
    this.canViewSensitivePrayers = false,
    this.canManageCareCases = false,
    this.canViewAssignedCareCases = false,
    this.canManageMembersBasic = false,
    this.canManageRoles = false,
    this.canViewFinance = false,
    this.canManageFinance = false,
    this.canManageMediaUploads = false,
    this.canManageServiceChecklists = false,
    this.canApproveHighImpactEvents = false,
  });

  // Factory to create from list of role IDs
  factory UserCapabilities.fromRoleIds(List<String> roleIds) {
    return UserCapabilities.fromRoleIdsAndPrivileges(roleIds, const []);
  }

  factory UserCapabilities.fromRoleIdsAndPrivileges(
    List<String> roleIds,
    List<String> privilegeIds,
  ) {
    // Start with all false
    bool createEvents = false;
    bool editEvents = false;
    bool publishAnnouncements = false;
    bool moderatePosts = false;
    bool manageSchedules = false;
    bool assignPrayers = false;
    bool viewSensitivePrayers = false;
    bool manageCareCases = false;
    bool viewAssignedCareCases = false;
    bool manageMembersBasic = false;
    bool manageRoles = false;
    bool viewFinance = false;
    bool manageFinance = false;
    bool manageMediaUploads = false;
    bool manageServiceChecklists = false;
    bool approveHighImpact = false;

    // Helper to normalize role strings (handle "Pastor" vs "pastor")
    List<String> normalizedRoles =
        roleIds.map((r) => r.toLowerCase().replaceAll(' ', '_')).toList();

    for (final role in normalizedRoles) {
      if (_matches(role, [
        'senior_pastor',
        'pastor',
        'assistant_pastor',
        'acting_pastor',
        'church_admin',
        'church_secretary',
        'secretary',
        'administrator',
        'admin'
      ])) {
        createEvents = true;
        editEvents = true;
        publishAnnouncements = true;
        manageMembersBasic = true;
        manageSchedules = true;
      }

      if (_matches(role, ['senior_pastor', 'pastor', 'acting_pastor'])) {
        moderatePosts = true;
        assignPrayers = true;
        approveHighImpact = true;
      }

      if (_matches(role, ['senior_pastor', 'pastor'])) {
        manageRoles = true;
      }

      if (_matches(role,
          ['assistant_pastor', 'church_admin', 'admin', 'administrator'])) {
        moderatePosts = true;
      }

      if (_matches(role, ['prayer_ministry_leader'])) {
        viewAssignedCareCases = true;
      }

      if (_matches(role, ['intercessor', 'prayer_warrior', 'elder'])) {
        viewAssignedCareCases = true;
      }

      if (_matches(role, [
        'care_counseling_coordinator',
        'deacon',
        'deaconess',
        'elder',
      ])) {
        viewAssignedCareCases = true;
      }

      if (_matches(role, ['pastor', 'senior_pastor', 'acting_pastor'])) {
        manageCareCases = true;
        viewAssignedCareCases = true;
      }

      if (_matches(role, ['counselor'])) {
        viewAssignedCareCases = true;
      }

      if (_matches(role, [
        'treasurer',
        'financial_secretary',
        'finance',
        'senior_pastor',
        'admin'
      ])) {
        viewFinance = true;
      }

      if (_matches(role,
          ['pastor', 'senior_pastor', 'treasurer', 'financial_secretary'])) {
        manageFinance = true;
      }

      if (_matches(role,
          ['head_usher', 'worship_leader', 'media_av_director', 'deacon'])) {
        manageSchedules = true;
        manageServiceChecklists = true;
      }

      if (_matches(
          role, ['media_av_director', 'media_team_member', 'media_team'])) {
        manageMediaUploads = true;
      }

      // Ministry titles are intentionally separate from app access. The role
      // editor can suggest privileges for leaders, but actual access comes
      // from the explicit appPrivileges grant saved on the user profile.
    }

    for (final privilege in privilegeIds) {
      switch (privilege.trim()) {
        case 'approveMembers':
          manageMembersBasic = true;
          break;
        case 'manageChurchSettings':
          manageMembersBasic = true;
          break;
        case 'manageRoles':
          manageRoles = true;
          break;
        case 'viewOperationalAnalytics':
          approveHighImpact = true;
          break;
        case 'viewFinanceDashboard':
          viewFinance = true;
          break;
        case 'manageFinances':
          viewFinance = true;
          manageFinance = true;
          break;
        case 'approveFinanceReports':
          viewFinance = true;
          manageFinance = true;
          break;
        case 'createAnnouncement':
          publishAnnouncements = true;
          break;
        case 'sendPushNotification':
          publishAnnouncements = true;
          break;
        case 'pinPost':
          publishAnnouncements = true;
          moderatePosts = true;
          break;
        case 'moderateCommunity':
          moderatePosts = true;
          break;
        case 'createEvents':
          createEvents = true;
          editEvents = true;
          break;
        case 'manageSundaySchool':
          createEvents = true;
          editEvents = true;
          break;
        case 'manageLivestream':
          manageMediaUploads = true;
          break;
        case 'manageWorship':
          manageServiceChecklists = true;
          break;
        case 'managePrayerRequests':
          viewAssignedCareCases = true;
          break;
        case 'assignCareRequests':
          assignPrayers = true;
          manageCareCases = true;
          viewAssignedCareCases = true;
          break;
        case 'manualCheckIn':
        case 'viewAttendanceInsights':
          manageSchedules = true;
          break;
        case 'viewPriorityList':
        case 'managePriorityList':
          manageCareCases = true;
          viewAssignedCareCases = true;
          break;
        case 'manageSchedule':
          manageSchedules = true;
          break;
      }
    }

    return UserCapabilities(
      canCreateEvents: createEvents,
      canEditEvents: editEvents,
      canPublishAnnouncements: publishAnnouncements,
      canModeratePosts: moderatePosts,
      canManageSchedules: manageSchedules,
      canAssignPrayers: assignPrayers,
      canViewSensitivePrayers: viewSensitivePrayers,
      canManageCareCases: manageCareCases,
      canViewAssignedCareCases: viewAssignedCareCases,
      canManageMembersBasic: manageMembersBasic,
      canManageRoles: manageRoles,
      canViewFinance: viewFinance,
      canManageFinance: manageFinance,
      canManageMediaUploads: manageMediaUploads,
      canManageServiceChecklists: manageServiceChecklists,
      canApproveHighImpactEvents: approveHighImpact,
    );
  }

  static bool _matches(String role, List<String> targets) {
    return targets.contains(role);
  }
}
