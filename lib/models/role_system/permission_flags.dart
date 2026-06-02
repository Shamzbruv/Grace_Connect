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
        assignPrayers = true;
        moderatePosts = true;
      }

      if (_matches(role, ['prayer_ministry_leader'])) {
        assignPrayers = true;
        viewSensitivePrayers = true;
      }

      if (_matches(role, ['intercessor', 'prayer_warrior', 'elder'])) {
        viewSensitivePrayers = true;
      }

      if (_matches(role, [
        'care_counseling_coordinator',
        'deacon',
        'deaconess',
        'elder',
        'admin',
        'church_admin',
        'pastor',
        'senior_pastor',
        'assistant_pastor',
        'acting_pastor'
      ])) {
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

      // Add Ministry Leaders (can create events for own ministry - handled by app logic usually,
      // but strictly speaking they have 'create event' power generally in this simple model,
      // or we rely on the specific 'canCreateEvents' flag being true)
      if (role.contains('_ministry_leader') || role.contains('_director')) {
        createEvents = true;
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
