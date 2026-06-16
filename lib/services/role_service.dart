import 'package:supabase_flutter/supabase_flutter.dart';

class RoleService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Calls the 'manageRole' cloud function
  Future<void> assignRole(
      String targetUid, String role, String churchId) async {
    try {
      await _supabase.rpc('assign_member_role', params: {
        'target_uid': targetUid,
        'role_name': role,
        'church_id': churchId,
        'role_action': 'add',
      });
    } catch (e) {
      throw Exception('Failed to assign role: $e');
    }
  }

  Future<void> removeRole(
      String targetUid, String role, String churchId) async {
    try {
      await _supabase.rpc('assign_member_role', params: {
        'target_uid': targetUid,
        'role_name': role,
        'church_id': churchId,
        'role_action': 'remove',
      });
    } catch (e) {
      throw Exception('Failed to remove role: $e');
    }
  }

  Future<void> updatePrivileges(
    String targetUid,
    Set<String> privileges,
    String churchId,
  ) async {
    try {
      await _supabase.rpc('assign_member_privileges', params: {
        'target_uid': targetUid,
        'privilege_names': privileges.toList()..sort(),
        'church_id': churchId,
      });
    } catch (e) {
      throw Exception('Failed to update privileges: $e');
    }
  }

  // Stream of audit logs for the church
  Stream<List<Map<String, dynamic>>> getAuditLogs(String churchId) {
    return _supabase
        .from('audit_logs')
        .stream(primaryKey: ['id'])
        .eq('churchId', churchId)
        .order('timestamp', ascending: false)
        .limit(250)
        .map((docs) => docs.toList());
  }
}
