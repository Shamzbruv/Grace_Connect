import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/study_group_model.dart';
import '../models/group_message_model.dart';
import '../models/user_profile.dart';

class StudyGroupService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Create Group
  Future<void> createGroup(StudyGroup group) async {
    await _supabase.from('study_groups').upsert(group.toMap());
  }

  Future<void> updateGroup(StudyGroup group) async {
    await _supabase
        .from('study_groups')
        .update(group.toMap())
        .eq('id', group.id);
  }

  // Get Groups for Church (Browse)
  Stream<List<StudyGroup>> getGroupsForChurch(String churchId) {
    return _supabase
        .from('study_groups')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .map((docs) => docs
            .map((doc) => StudyGroup.fromMap(doc))
            .where((group) => !group.isPrivate)
            .toList());
  }

  // Get My Groups (where array-contains UID)
  Stream<List<StudyGroup>> getMyGroups(String uid) {
    return _supabase.from('study_groups').stream(primaryKey: ['id']).map(
        (docs) => docs
            .where((doc) =>
                (doc['memberIds'] as List<dynamic>?)?.contains(uid) == true ||
                (doc['adminIds'] as List<dynamic>?)?.contains(uid) == true ||
                doc['leaderId'] == uid)
            .map((doc) => StudyGroup.fromMap(doc))
            .toList());
  }

  // Join Group
  Future<String> joinGroup(String groupId, String uid) async {
    if (uid.isEmpty) return 'ignored';
    final result = await _supabase
        .rpc('join_study_group', params: {'target_group_id': groupId});
    return (result ?? 'active').toString();
  }

  // Leave Group
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

  // Send Message
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

  // Get Messages
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
}
