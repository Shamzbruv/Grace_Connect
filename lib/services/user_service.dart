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
    final cleanUid = uid.trim();
    if (cleanUid.isEmpty) return null;

    try {
      final doc = await _supabase
          .from('users')
          .select()
          .eq('uid', cleanUid)
          .maybeSingle();
      if (doc != null) {
        return UserProfile.fromMap(doc);
      }

      if (_looksLikeUuid(cleanUid)) {
        final idDoc = await _supabase
            .from('users')
            .select()
            .eq('id', cleanUid)
            .maybeSingle();
        if (idDoc != null) {
          return UserProfile.fromMap(idDoc);
        }
      }

      if (cleanUid.contains('@')) {
        final emailDoc = await _supabase
            .from('users')
            .select()
            .ilike('email', cleanUid)
            .maybeSingle();
        if (emailDoc != null) {
          return UserProfile.fromMap(emailDoc);
        }
      }

      return null;
    } catch (e) {
      debugPrint('Failed to fetch user profile: $e');
      return null;
    }
  }

  Future<UserProfile?> findBestPersonMatch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    final direct = await getUserProfile(cleanQuery);
    if (direct != null) return direct;

    final results = await searchPeople(cleanQuery);
    if (results.isEmpty) return null;

    final lower = cleanQuery.toLowerCase();
    return results.firstWhere(
      (person) =>
          person.fullName.toLowerCase() == lower ||
          person.email.toLowerCase() == lower,
      orElse: () => results.first,
    );
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
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

  Future<List<UserProfile>> searchPeople(String query) async {
    final cleanQuery = query.trim().replaceAll(',', ' ');
    if (cleanQuery.length < 2) return [];

    try {
      final rows = await _supabase.rpc(
        'search_people_global',
        params: {
          'search_query': cleanQuery,
          'result_limit': 30,
        },
      );
      return (rows as List)
          .map((doc) => UserProfile.fromMap(Map<String, dynamic>.from(doc)))
          .toList();
    } catch (error) {
      debugPrint('Global people search fallback: $error');
    }

    final safeQuery = cleanQuery
        .replaceAll(RegExp(r'[%(),]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final snapshot = await _supabase
        .from('users')
        .select()
        .or('fullName.ilike.%$safeQuery%,'
            'email.ilike.%$safeQuery%,'
            'placeName.ilike.%$safeQuery%')
        .order('fullName')
        .limit(30);
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
