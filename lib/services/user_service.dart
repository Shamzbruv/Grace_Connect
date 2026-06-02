import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Stream<UserProfile> getUserProfileStream(String uid) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .map((docs) {
          if (docs.isNotEmpty) {
            return UserProfile.fromMap(docs.first);
          }
          throw Exception('User not found');
        });
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      final doc =
          await _supabase.from('users').select().eq('uid', uid).maybeSingle();
      if (doc != null) {
        return UserProfile.fromMap(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Failed to fetch user profile: $e');
      return null;
    }
  }

  Future<void> updateProfile(UserProfile profile) async {
    try {
      await _supabase
          .from('users')
          .update(profile.toMap())
          .eq('uid', profile.uid);
    } catch (e) {
      debugPrint('Failed to update profile: $e');
    }
  }

  Future<List<UserProfile>> searchMembers(String query, String placeId) async {
    final cleanQuery = query.trim().replaceAll(',', ' ');
    if (cleanQuery.isEmpty) return [];
    final snapshot = await _supabase
        .from('users')
        .select()
        .eq('placeId', placeId)
        .or('fullName.ilike.%$cleanQuery%,email.ilike.%$cleanQuery%')
        .order('fullName')
        .limit(10);
    return snapshot.map((doc) => UserProfile.fromMap(doc)).toList();
  }

  Stream<List<UserProfile>> getMembers(String churchId) {
    return _supabase
        .from('users')
        .stream(primaryKey: ['uid'])
        .eq('placeId', churchId)
        .order('fullName')
        .map((docs) => docs.map((doc) => UserProfile.fromMap(doc)).toList());
  }

  Future<void> updateMemberRole(String userId, List<String> roles) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return;

      final actor = await _supabase
          .from('users')
          .select('placeId')
          .eq('uid', currentUserId)
          .maybeSingle();
      final churchId = actor?['placeId'];
      if (churchId == null || churchId.toString().isEmpty) return;

      final currentTarget = await _supabase
          .from('users')
          .select('roles')
          .eq('uid', userId)
          .maybeSingle();
      final currentRoles =
          List<String>.from(currentTarget?['roles'] ?? const []);

      for (final role in currentRoles) {
        if (!roles.contains(role)) {
          await _supabase.rpc('assign_member_role', params: {
            'target_uid': userId,
            'role_name': role,
            'church_id': churchId,
            'role_action': 'remove',
          });
        }
      }

      for (final role in roles) {
        if (!currentRoles.contains(role)) {
          await _supabase.rpc('assign_member_role', params: {
            'target_uid': userId,
            'role_name': role,
            'church_id': churchId,
            'role_action': 'add',
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to update member role: $e');
    }
  }
}
