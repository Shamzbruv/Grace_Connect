import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/study_group_model.dart';
import '../models/group_message_model.dart';

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
                (doc['memberIds'] as List<dynamic>?)?.contains(uid) == true)
            .map((doc) => StudyGroup.fromMap(doc))
            .toList());
  }

  // Join Group
  Future<void> joinGroup(String groupId, String uid) async {
    if (uid.isEmpty) return;
    await _supabase
        .rpc('join_study_group', params: {'target_group_id': groupId});
  }

  // Leave Group
  Future<void> leaveGroup(String groupId, String uid) async {
    if (uid.isEmpty) return;
    await _supabase
        .rpc('leave_study_group', params: {'target_group_id': groupId});
  }

  // Send Message
  Future<void> sendMessage(
      String groupId, String senderId, String senderName, String text) async {
    if (text.trim().isEmpty) return;
    await _supabase.from('group_messages').insert({
      'id': const Uuid().v4(),
      'groupId': groupId,
      'senderId': senderId,
      'senderName': senderName,
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
