import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/group_message_model.dart';
import '../models/study_group_announcement.dart';
import '../models/study_group_model.dart';
import '../models/study_group_resource.dart';
import '../models/study_reading_assignment.dart';
import '../models/study_reading_plan.dart';
import '../models/user_profile.dart';
import 'study_group_access_service.dart';

class StudyGroupsSetupException implements Exception {
  final String message;
  const StudyGroupsSetupException(this.message);

  @override
  String toString() => message;
}

class StudyGroupService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<StudyGroup> createGroup(StudyGroup group) async {
    try {
      final result = await _supabase.rpc(
        'create_study_group',
        params: {'group_payload': group.toMap()},
      );
      final created = _firstMap(result);
      if (created != null) return StudyGroup.fromMap(created);
      return group;
    } catch (error) {
      if (!_isMissingRpc(error)) rethrow;
      await _supabase.from('study_groups').upsert(_legacyGroupMap(group));
      return group;
    }
  }

  Future<StudyGroup> updateGroup(StudyGroup group) async {
    try {
      final result = await _supabase.rpc(
        'update_study_group',
        params: {
          'target_group_id': group.id,
          'group_payload': group.toMap(),
        },
      );
      final updated = _firstMap(result);
      if (updated != null) return StudyGroup.fromMap(updated);
      return group;
    } catch (error) {
      if (!_isMissingRpc(error)) rethrow;
      try {
        await _supabase
            .from('study_groups')
            .update(group.toMap())
            .eq('id', group.id);
      } on PostgrestException catch (legacyError) {
        if (!_isMissingColumn(legacyError)) rethrow;
        await _supabase
            .from('study_groups')
            .update(_legacyGroupMap(group))
            .eq('id', group.id);
      }
      return group;
    }
  }

  Future<void> deleteGroup(
    String groupId, {
    required String confirmationName,
  }) async {
    if (groupId.trim().isEmpty) {
      throw ArgumentError('Group ID is required.');
    }

    try {
      await _supabase.rpc(
        'delete_study_group',
        params: {
          'target_group_id': groupId.trim(),
          'confirmation_name': confirmationName.trim(),
        },
      );
    } catch (error) {
      if (_isMissingRpc(error) || _isMissingColumn(error)) {
        throw const StudyGroupsSetupException(
          'Study Group archiving is still being configured. Please apply the latest Supabase migration and try again.',
        );
      }
      rethrow;
    }
  }

  Stream<List<StudyGroup>> getGroupsForChurch(String churchId) {
    if (churchId.trim().isEmpty) return Stream.value(const []);
    return _watchChurchGroups(churchId).map(
      (groups) => groups
          .where(
            (group) =>
                !group.isArchived &&
                group.visibility == 'church' &&
                group.joinMode != 'closed',
          )
          .toList(),
    );
  }

  Stream<List<StudyGroup>> getMyGroups(String uid) {
    if (uid.trim().isEmpty) return Stream.value(const []);
    return _watchAllGroups().map(
      (groups) => groups
          .where(
            (group) =>
                !group.isArchived &&
                StudyGroupAccessService.isMemberOf(group, uid),
          )
          .toList(),
    );
  }

  Stream<List<StudyGroup>> getInvitations(String uid) {
    if (uid.trim().isEmpty) return Stream.value(const []);
    return _watchAllGroups().map(
      (groups) => groups
          .where(
            (group) =>
                !group.isArchived &&
                StudyGroupAccessService.isPendingIn(group, uid),
          )
          .toList(),
    );
  }

  Stream<List<StudyGroup>> getManagedGroups({
    required UserProfile? profile,
    required String currentUserId,
  }) {
    final churchId = profile?.placeId ?? '';
    if (churchId.trim().isEmpty || currentUserId.trim().isEmpty) {
      return Stream.value(const []);
    }

    return _watchChurchGroups(churchId).map(
      (groups) => groups
          .where(
            (group) =>
                !group.isArchived &&
                StudyGroupAccessService.forGroup(
                  group: group,
                  currentUserId: currentUserId,
                  profile: profile,
                ).canOpenSettings,
          )
          .toList(),
    );
  }

  Stream<List<StudyGroup>> getVisibleGroupsForChurch(String churchId) {
    return getGroupsForChurch(churchId);
  }

  Future<List<StudyGroup>> fetchVisibleStudyGroups() async {
    try {
      final result = await _supabase.rpc('get_visible_study_groups');
      final rows = result is List ? result : const [];
      return rows
          .whereType<Map>()
          .map((row) => StudyGroup.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      if (_isMissingRpc(error) || _isMissingTable(error)) return const [];
      rethrow;
    }
  }

  Future<String> joinGroup(String groupId, String uid) async {
    if (uid.isEmpty) return 'ignored';
    dynamic result;
    try {
      result = await _supabase.rpc(
        'request_to_join_study_group',
        params: {'target_group_id': groupId},
      );
    } catch (error) {
      if (!_isMissingRpc(error)) rethrow;
      result = await _supabase.rpc(
        'join_study_group',
        params: {'target_group_id': groupId},
      );
    }
    return (result ?? 'active').toString();
  }

  Future<void> leaveGroup(String groupId, String uid) async {
    if (uid.isEmpty) return;
    await _supabase
        .rpc('leave_study_group', params: {'target_group_id': groupId});
  }

  Future<void> approvePendingMember(String groupId, String userId) async {
    if (groupId.isEmpty || userId.isEmpty) return;
    await _supabase.rpc(
      'approve_study_group_member',
      params: {
        'target_group_id': groupId,
        'target_user_id': userId,
      },
    );
  }

  Future<void> declinePendingMember(String groupId, String userId) async {
    if (groupId.isEmpty || userId.isEmpty) return;
    await _supabase.rpc(
      'decline_study_group_member',
      params: {
        'target_group_id': groupId,
        'target_user_id': userId,
      },
    );
  }

  Future<void> setGroupAdmin(
    String groupId,
    String userId, {
    required bool makeAdmin,
  }) async {
    if (groupId.isEmpty || userId.isEmpty) return;
    await _supabase.rpc(
      'set_study_group_admin',
      params: {
        'target_group_id': groupId,
        'target_user_id': userId,
        'make_admin': makeAdmin,
      },
    );
  }

  Future<List<UserProfile>> fetchGroupMembers(List<String> userIds) async {
    final cleanIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cleanIds.isEmpty) return const [];

    final rows = await _supabase
        .from('users')
        .select()
        .inFilter('uid', cleanIds)
        .order('fullName');
    return rows.map<UserProfile>((row) => UserProfile.fromMap(row)).toList();
  }

  Future<void> sendMessage(
    String groupId,
    String senderId,
    String senderName,
    String text, {
    String senderPhotoUrl = '',
  }) async {
    if (text.trim().isEmpty) return;
    await _supabase.from('group_messages').insert({
      'id': const Uuid().v4(),
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'text': text.trim(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Stream<List<GroupMessage>> getMessages(String groupId) {
    return _supabase
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('groupId', groupId)
        .order('timestamp', ascending: false)
        .map((docs) {
          final messagesById = <String, GroupMessage>{};
          for (final doc in docs) {
            final message = GroupMessage.fromMap(doc);
            if (message.id.isNotEmpty) {
              messagesById[message.id] = message;
            }
          }
          return messagesById.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
  }

  Future<List<StudyReadingPlan>> fetchReadingPlans(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      final rows = await _supabase
          .from('study_group_reading_plans')
          .select()
          .eq('group_id', groupId)
          .neq('status', 'archived')
          .order('created_at', ascending: false);
      return rows
          .map<StudyReadingPlan>((row) => StudyReadingPlan.fromMap(row))
          .toList();
    } catch (error) {
      if (_isMissingTable(error)) return const [];
      rethrow;
    }
  }

  Future<List<StudyReadingAssignment>> fetchReadingAssignments(
    String planId,
  ) async {
    if (planId.isEmpty) return const [];
    try {
      final rows = await _supabase
          .from('study_group_reading_assignments')
          .select()
          .eq('plan_id', planId)
          .order('sequence_number');
      return rows
          .map<StudyReadingAssignment>(
            (row) => StudyReadingAssignment.fromMap(row),
          )
          .toList();
    } catch (error) {
      if (_isMissingTable(error)) return const [];
      rethrow;
    }
  }

  Future<String> createReadingPlan({
    required String groupId,
    required String title,
    String description = '',
    String translation = 'KJV',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final result = await _supabase.rpc(
      'create_study_group_reading_plan',
      params: {
        'plan_payload': {
          'groupId': groupId,
          'title': title,
          'description': description,
          'translation': translation,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'status': 'active',
        },
      },
    );
    return result?.toString() ?? '';
  }

  Future<void> markAssignmentComplete(
    String assignmentId, {
    String reflection = '',
  }) async {
    await _supabase.rpc(
      'mark_study_assignment_complete',
      params: {
        'target_assignment_id': assignmentId,
        'reflection_text': reflection.trim().isEmpty ? null : reflection.trim(),
      },
    );
  }

  Future<List<StudyGroupAnnouncement>> fetchAnnouncements(
      String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      final rows = await _supabase
          .from('study_group_announcements')
          .select()
          .eq('group_id', groupId)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(20);
      return rows
          .map<StudyGroupAnnouncement>(
            (row) => StudyGroupAnnouncement.fromMap(row),
          )
          .toList();
    } catch (error) {
      if (_isMissingTable(error)) return const [];
      rethrow;
    }
  }

  Future<List<StudyGroupResource>> fetchResources(String groupId) async {
    if (groupId.isEmpty) return const [];
    try {
      final rows = await _supabase
          .from('study_group_resources')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false);
      return rows
          .map<StudyGroupResource>((row) => StudyGroupResource.fromMap(row))
          .toList();
    } catch (error) {
      if (_isMissingTable(error)) return const [];
      rethrow;
    }
  }

  Stream<List<StudyGroup>> _watchChurchGroups(String churchId) {
    return _supabase
        .from('study_groups')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .map(_mapGroups);
  }

  Stream<List<StudyGroup>> _watchAllGroups() {
    return _supabase
        .from('study_groups')
        .stream(primaryKey: ['id']).map(_mapGroups);
  }

  List<StudyGroup> _mapGroups(List<Map<String, dynamic>> docs) {
    final groups = docs.map(StudyGroup.fromMap).toList();
    groups.sort((a, b) {
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });
    return groups;
  }

  Map<String, dynamic> _legacyGroupMap(StudyGroup group) {
    return {
      'name': group.name,
      'topic': group.topic,
      'description': group.description,
      'leaderId': group.leaderId,
      'leaderName': group.leaderName,
      'adminIds': group.adminIds,
      'memberIds': group.memberIds,
      'pendingMemberIds': group.pendingMemberIds,
      'schedule': group.schedule,
      'churchId': group.churchId,
      'id': group.id,
      'createdAt': group.createdAt.toIso8601String(),
      'allowMemberMessages': group.allowMemberMessages,
      'isPrivate': group.visibility != 'church',
      'requireJoinApproval':
          group.joinMode == 'approval' || group.joinMode == 'invitation_only',
    };
  }

  Map<String, dynamic>? _firstMap(dynamic result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  bool _isMissingRpc(Object error) {
    return error is PostgrestException &&
        (error.code == 'PGRST202' ||
            error.message.contains('Could not find the function'));
  }

  bool _isMissingTable(Object error) {
    return error is PostgrestException &&
        (error.code == 'PGRST205' ||
            error.message.contains('Could not find the table'));
  }

  bool _isMissingColumn(Object error) {
    return error is PostgrestException &&
        (error.code == 'PGRST204' ||
            error.code == '42703' ||
            error.message.contains('column') &&
                error.message.contains('does not exist'));
  }
}
