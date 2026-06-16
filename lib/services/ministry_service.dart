import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ministry.dart';
import '../models/user_profile.dart';

class MinistryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool canManageMinistrySetup(UserProfile? user) {
    if (user == null) return false;
    final roles = user.roles.map(_normalizeRole).toSet();
    return roles.contains('pastor') || roles.contains('senior_pastor');
  }

  bool hasLeadershipRole(UserProfile? user) {
    if (user == null) return false;
    return user.capabilities.canCreateEvents ||
        user.capabilities.canPublishAnnouncements ||
        canManageMinistrySetup(user);
  }

  Future<bool> canCreateEvents(UserProfile? user) async {
    if (user == null) return false;
    if (user.capabilities.canCreateEvents) return true;
    return managesAnyMinistry(capability: 'events');
  }

  Future<bool> canPublishAnnouncements(UserProfile? user) async {
    if (user == null) return false;
    if (user.capabilities.canPublishAnnouncements) return true;
    return managesAnyMinistry(capability: 'announcements');
  }

  Future<bool> managesAnyMinistry({String? capability}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return false;

    try {
      final result = await _supabase.rpc(
        'is_ministry_manager',
        params: {
          'target_church_id': null,
          'target_ministry_id': null,
          'required_capability': capability,
        },
      );
      return result == true;
    } catch (error) {
      debugPrint('Could not check ministry manager permission: $error');
      return false;
    }
  }

  Stream<List<Ministry>> watchMinistries(String churchId) {
    if (churchId.isEmpty) return const Stream.empty();
    return _supabase
        .from('ministries')
        .stream(primaryKey: ['id'])
        .eq('church_id', churchId)
        .order('name')
        .map((rows) => rows.map((row) => Ministry.fromMap(row)).toList());
  }

  Future<List<Ministry>> fetchMinistries(String churchId) async {
    if (churchId.isEmpty) return [];
    final rows = await _supabase
        .from('ministries')
        .select()
        .eq('church_id', churchId)
        .order('name');
    return rows.map<Ministry>((row) => Ministry.fromMap(row)).toList();
  }

  Future<List<MinistryManager>> fetchMinistryManagers(
    String ministryId,
  ) async {
    if (ministryId.isEmpty) return [];
    final rows = await _supabase.rpc('get_ministry_managers',
        params: {'target_ministry_id': ministryId});
    return (rows as List<dynamic>)
        .map((row) => MinistryManager.fromMap(Map<String, dynamic>.from(row)))
        .where((manager) => manager.isActive)
        .toList();
  }

  Future<List<MinistryManager>> fetchMyManagedMinistries() async {
    try {
      final rows = await _supabase.rpc('get_my_managed_ministries');
      return (rows as List<dynamic>)
          .map((row) => MinistryManager.fromMap(Map<String, dynamic>.from(row)))
          .where((manager) => manager.isActive)
          .toList();
    } catch (error) {
      debugPrint('Could not fetch managed ministries: $error');
      return [];
    }
  }

  Future<Ministry> createMinistry({
    required String name,
    String description = '',
  }) async {
    final row = await _supabase.rpc(
      'create_ministry',
      params: {
        'ministry_name': name.trim(),
        'ministry_description': description.trim(),
      },
    );
    return Ministry.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> updateMinistry({
    required Ministry ministry,
    required String name,
    required String description,
    required String status,
  }) async {
    await _supabase.from('ministries').update({
      'name': name.trim(),
      'description': description.trim(),
      'status': status,
    }).eq('id', ministry.id);
  }

  Future<MinistryManager> assignManager({
    required String ministryId,
    required String userId,
    required String roleTitle,
    required bool canCreateEvents,
    required bool canPublishAnnouncements,
  }) async {
    final row = await _supabase.rpc(
      'assign_ministry_manager',
      params: {
        'target_ministry_id': ministryId,
        'target_user_id': userId,
        'manager_role_title':
            roleTitle.trim().isEmpty ? 'Ministry Manager' : roleTitle.trim(),
        'allow_events': canCreateEvents,
        'allow_announcements': canPublishAnnouncements,
      },
    );
    return MinistryManager.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> removeManager(String managerId) async {
    await _supabase.rpc(
      'revoke_ministry_manager',
      params: {'manager_assignment_id': managerId},
    );
  }

  Future<List<UserProfile>> searchMembers({
    required String churchId,
    required String query,
  }) async {
    final cleanQuery = query.trim().replaceAll(',', ' ');
    if (churchId.isEmpty || cleanQuery.length < 2) return [];

    final rows = await _supabase
        .from('users')
        .select()
        .eq('placeId', churchId)
        .or('fullName.ilike.%$cleanQuery%,email.ilike.%$cleanQuery%')
        .order('fullName')
        .limit(12);
    return rows.map<UserProfile>((row) => UserProfile.fromMap(row)).toList();
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
