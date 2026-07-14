import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/social_profile.dart';
import '../models/user_profile.dart';
import 'user_service.dart';

class SocialProfileService {
  SocialProfileService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;
  final UserService _userService = UserService();

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<SocialProfile?> fetchProfile(String userId) async {
    final cleanUserId = userId.trim();
    if (cleanUserId.isEmpty) return null;

    try {
      final row = await _supabase
          .from('social_profiles')
          .select()
          .eq('user_id', cleanUserId)
          .maybeSingle();
      if (row != null) return SocialProfile.fromMap(row);
    } catch (error) {
      debugPrint('Social profile table unavailable: $error');
    }

    final userProfile = await _userService.getUserProfile(cleanUserId);
    if (userProfile != null) return SocialProfile.fromUserProfile(userProfile);

    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null || currentUser.id != cleanUserId) return null;

    final metadata = currentUser.userMetadata ?? const <String, dynamic>{};
    final displayName = _firstString(metadata, const [
          'display_name',
          'displayName',
          'full_name',
          'fullName',
          'name',
        ]) ??
        (currentUser.email?.split('@').first.trim().isNotEmpty == true
            ? currentUser.email!.split('@').first.trim()
            : 'Grace Connect Member');

    return SocialProfile(
      userId: currentUser.id,
      displayName: displayName,
      avatarUrl: _firstString(
            metadata,
            const ['avatar_url', 'picture', 'photoUrl', 'photo_url'],
          ) ??
          '',
      acceptsMessages: true,
    );
  }

  Future<SocialProfile?> fetchCurrentProfile() async {
    final userId = currentUserId;
    if (userId == null) return null;
    return fetchProfile(userId);
  }

  Future<SocialProfile> ensureProfile(UserProfile profile) async {
    final socialProfile = SocialProfile.fromUserProfile(profile);
    try {
      await _supabase
          .from('social_profiles')
          .upsert(socialProfile.toMap(), onConflict: 'user_id');
    } catch (error) {
      debugPrint('Could not sync social profile yet: $error');
    }
    return socialProfile;
  }

  Future<void> updateProfile(SocialProfile profile) async {
    final userId = currentUserId;
    if (userId == null || userId != profile.userId) {
      throw StateError('You can only update your own public profile.');
    }

    try {
      await _supabase
          .from('social_profiles')
          .upsert(profile.toMap(), onConflict: 'user_id');
    } catch (error) {
      debugPrint('Social profile update failed: $error');
      rethrow;
    }
  }

  Future<String> followStatus(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null ||
        targetUserId.trim().isEmpty ||
        userId == targetUserId) {
      return 'self';
    }

    try {
      final row = await _supabase
          .from('social_follows')
          .select('status')
          .eq('follower_id', userId)
          .eq('following_id', targetUserId)
          .maybeSingle();
      return row?['status']?.toString() ?? 'none';
    } catch (error) {
      debugPrint('Follow status unavailable: $error');
      final localFollowing = await _localFollowingIds(userId);
      return localFollowing.contains(targetUserId) ? 'accepted' : 'none';
    }
  }

  Future<void> requestFollow(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null ||
        targetUserId.trim().isEmpty ||
        userId == targetUserId) {
      return;
    }

    try {
      await _supabase.rpc(
        'request_social_follow',
        params: {'target_user_id': targetUserId},
      );
      return;
    } catch (error) {
      debugPrint('Follow RPC unavailable, using direct insert: $error');
    }

    try {
      await _supabase.from('social_follows').upsert(
        {
          'follower_id': userId,
          'following_id': targetUserId,
          'status': 'accepted',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'follower_id,following_id',
      );
    } catch (error) {
      debugPrint('Follow table unavailable, using local follow: $error');
      await _saveLocalFollow(userId, targetUserId);
    }
  }

  Future<void> removeFollow(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null || targetUserId.trim().isEmpty) return;

    try {
      await _supabase
          .from('social_follows')
          .delete()
          .eq('follower_id', userId)
          .eq('following_id', targetUserId);
    } catch (error) {
      debugPrint('Follow table unavailable, removing local follow: $error');
    }
    await _removeLocalFollow(userId, targetUserId);
  }

  static String localFollowKey(String userId) => 'local_social_follows_$userId';

  Future<Set<String>> _localFollowingIds(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(localFollowKey(userId)) ?? const [])
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<void> _saveLocalFollow(String userId, String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = localFollowKey(userId);
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()
      ..add(targetUserId);
    await prefs.setStringList(key, ids.toList());
  }

  Future<void> _removeLocalFollow(String userId, String targetUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = localFollowKey(userId);
    final ids = (prefs.getStringList(key) ?? <String>[]).toSet()
      ..remove(targetUserId);
    await prefs.setStringList(key, ids.toList());
  }

  String? _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
