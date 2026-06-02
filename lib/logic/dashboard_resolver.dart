// If ChurchRole is just a model, we might need a way to check hierarchy.
// For now, we'll define the logic here based on string matching or ID matching from the Registry.

enum DashboardType {
  pastor,
  admin,
  finance,
  ministryLeader,
  ministryWorker,
  member,
  // We can add deacon/usher specific if they diverge significantly from MinistryWorker or Admin
  care, // For Deacons/Deaconesses
  service, // For Ushers/Greeters
}

class DashboardResolver {
  static DashboardType resolve(List<String> roleNames) {
    if (roleNames.isEmpty) return DashboardType.member;

    final roles = roleNames.map(_normalizeRole).toList();

    // 1. Executive / Pastor (Highest Priority)
    if (roles.any((r) =>
        r == 'senior_pastor' ||
        r == 'pastor' ||
        r == 'assistant_pastor' ||
        r == 'acting_pastor' ||
        r == 'elder')) {
      return DashboardType.pastor;
    }

    // 2. Admin / Operations
    if (roles.any((r) =>
        r == 'admin' ||
        r == 'administrator' ||
        r == 'church_admin' ||
        r == 'church_secretary' ||
        r == 'secretary' ||
        r.contains('clerk'))) {
      return DashboardType.admin;
    }

    // 3. Finance
    if (roles.any((r) =>
        r == 'treasurer' ||
        r == 'financial_secretary' ||
        r.contains('finance'))) {
      return DashboardType.finance;
    }

    // 4. Care (Deacons)
    if (roles.any((r) => r.contains('deacon') || r.contains('welfare'))) {
      return DashboardType.care;
    }

    // 5. Ministry Leaders
    if (roles.any((r) =>
        r.contains('ministry_leader') ||
        r.contains('director') ||
        r.contains('superintendent') ||
        r.contains('leader') ||
        r.contains('coordinator'))) {
      return DashboardType.ministryLeader;
    }

    // 6. Service (Ushers/Greeters)
    if (roles.any((r) =>
        r.contains('usher') ||
        r.contains('greeter') ||
        r.contains('protocol'))) {
      return DashboardType.service;
    }

    // 7. Workers / Volunteers
    if (roles.any((r) =>
        r.contains('worker') ||
        r.contains('volunteer') ||
        r.contains('teacher') ||
        r.contains('team_member') ||
        r == 'media_team')) {
      return DashboardType.ministryWorker;
    }

    // Default
    return DashboardType.member;
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
