import '../models/study_group_model.dart';
import '../models/user_profile.dart';

class StudyGroupAccess {
  const StudyGroupAccess({
    required this.isGroupLeader,
    required this.isGroupAdmin,
    required this.isChurchLeader,
    required this.canManageStudyGroups,
    required this.canDeleteStudyGroups,
  });

  final bool isGroupLeader;
  final bool isGroupAdmin;
  final bool isChurchLeader;
  final bool canManageStudyGroups;
  final bool canDeleteStudyGroups;

  bool get canOpenSettings =>
      isGroupLeader || isGroupAdmin || isChurchLeader || canManageStudyGroups;

  bool get canManageMembers =>
      isGroupLeader || isGroupAdmin || isChurchLeader || canManageStudyGroups;

  bool get canEditGroup =>
      isGroupLeader || isGroupAdmin || isChurchLeader || canManageStudyGroups;

  bool get canDeleteGroup =>
      isGroupLeader || isGroupAdmin || isChurchLeader || canDeleteStudyGroups;
}

class StudyGroupAccessService {
  static const Set<String> _leaderRoles = {
    'pastor',
    'senior_pastor',
    'assistant_pastor',
    'acting_pastor',
    'church_administrator',
    'church_admin',
    'administrator',
    'admin',
  };

  static const Set<String> _createPrivileges = {
    'createStudyGroups',
    'manageStudyGroups',
  };

  static const Set<String> _managePrivileges = {
    'manageStudyGroups',
    'moderateStudyGroups',
    'approveStudyGroupMembers',
  };

  static const Set<String> _deletePrivileges = {
    'deleteStudyGroups',
  };

  static StudyGroupAccess forGroup({
    required StudyGroup group,
    required String currentUserId,
    required UserProfile? profile,
  }) {
    final isGroupLeader =
        currentUserId.isNotEmpty && group.leaderId == currentUserId;
    final isGroupAdmin =
        currentUserId.isNotEmpty && group.adminIds.contains(currentUserId);
    final isChurchLeader = hasChurchStudyGroupLeadership(profile);
    final privileges = profile?.appPrivileges.toSet() ?? const <String>{};

    return StudyGroupAccess(
      isGroupLeader: isGroupLeader,
      isGroupAdmin: isGroupAdmin,
      isChurchLeader: isChurchLeader,
      canManageStudyGroups:
          privileges.intersection(_managePrivileges).isNotEmpty ||
              profile?.capabilities.canManageMembersBasic == true,
      canDeleteStudyGroups:
          privileges.intersection(_deletePrivileges).isNotEmpty,
    );
  }

  static bool canCreateStudyGroups(UserProfile? profile) {
    if (profile == null) return false;
    final privileges = profile.appPrivileges.toSet();
    return hasChurchStudyGroupLeadership(profile) ||
        privileges.intersection(_createPrivileges).isNotEmpty ||
        profile.capabilities.canManageMembersBasic;
  }

  static bool canManageAtLeastOne({
    required Iterable<StudyGroup> groups,
    required String currentUserId,
    required UserProfile? profile,
  }) {
    return groups.any(
      (group) => forGroup(
        group: group,
        currentUserId: currentUserId,
        profile: profile,
      ).canOpenSettings,
    );
  }

  static bool hasChurchStudyGroupLeadership(UserProfile? profile) {
    if (profile == null) return false;
    if (profile.isDeveloper) return true;
    if (profile.hasPastoralRole) return true;
    return profile.roles.map(_normalizeRole).any(_leaderRoles.contains);
  }

  static bool isMemberOf(StudyGroup group, String userId) {
    if (userId.isEmpty) return false;
    return group.leaderId == userId ||
        group.adminIds.contains(userId) ||
        group.memberIds.contains(userId);
  }

  static bool isPendingIn(StudyGroup group, String userId) {
    return userId.isNotEmpty && group.pendingMemberIds.contains(userId);
  }

  static String membershipLabel(StudyGroup group, String userId) {
    if (userId.isEmpty) return '';
    if (group.leaderId == userId) return 'Leader';
    if (group.adminIds.contains(userId)) return 'Admin';
    if (group.memberIds.contains(userId)) return 'Member';
    if (group.pendingMemberIds.contains(userId)) return 'Request Pending';
    return '';
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
