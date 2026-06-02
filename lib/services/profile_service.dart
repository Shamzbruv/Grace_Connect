import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Upload Profile Photo (File - Mobile)
  Future<String> uploadProfilePhoto(File imageFile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final String path = '${user.id}/profile/profile.jpg';

    try {
      await _supabase.storage.from('avatars').upload(path, imageFile,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true));

      final downloadUrl = _supabase.storage.from('avatars').getPublicUrl(path);

      try {
        await _supabase
            .from('users')
            .update({'photoUrl': downloadUrl}).eq('uid', user.id);
      } catch (e) {
        debugPrint('Failed to sync profile photo URL: $e');
      }

      // Update Auth Profile (optional, but good for quick access)
      await _supabase.auth.updateUser(UserAttributes(
        data: {'avatar_url': downloadUrl},
      ));

      return downloadUrl;
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  // Upload Profile Photo (Bytes - Web/Mobile)
  Future<String> uploadProfilePhotoBytes(
      Uint8List imageBytes, String fileName) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final String path = '${user.id}/profile/$fileName';

    try {
      await _supabase.storage.from('avatars').uploadBinary(path, imageBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true));

      final downloadUrl = _supabase.storage.from('avatars').getPublicUrl(path);

      try {
        await _supabase
            .from('users')
            .update({'photoUrl': downloadUrl}).eq('uid', user.id);
      } catch (e) {
        debugPrint('Failed to sync profile photo URL: $e');
      }

      // Update Auth Profile (optional, but good for quick access)
      await _supabase.auth.updateUser(UserAttributes(
        data: {'avatar_url': downloadUrl},
      ));

      return downloadUrl;
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }

  // Upload Cover Photo (Optional)
  Future<String> uploadCoverPhoto(File imageFile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final String path =
        '${user.id}/cover/cover.jpg'; // Fixed filename for simple replace

    try {
      await _supabase.storage.from('avatars').upload(path, imageFile,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true));

      final downloadUrl = _supabase.storage.from('avatars').getPublicUrl(path);

      try {
        await _supabase
            .from('users')
            .update({'coverPhotoUrl': downloadUrl}).eq('uid', user.id);
      } catch (e) {
        debugPrint('Failed to sync cover photo URL: $e');
      }

      return downloadUrl;
    } catch (e) {
      throw Exception('Cover upload failed: $e');
    }
  }

  // Upload Cover Photo (Bytes - Web/Mobile)
  Future<String> uploadCoverPhotoBytes(
      Uint8List imageBytes, String fileName) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final String path = '${user.id}/cover/$fileName';

    try {
      await _supabase.storage.from('avatars').uploadBinary(path, imageBytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true));

      final downloadUrl = _supabase.storage.from('avatars').getPublicUrl(path);

      try {
        await _supabase
            .from('users')
            .update({'coverPhotoUrl': downloadUrl}).eq('uid', user.id);
      } catch (e) {
        debugPrint('Failed to sync cover photo URL: $e');
      }

      return downloadUrl;
    } catch (e) {
      throw Exception('Cover upload failed: $e');
    }
  }

  // Update Profile Data
  Future<void> updateProfile(UserProfile profile) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // Ensure we are updating the correct doc
    if (profile.uid != user.id) throw Exception('Unauthorized update');

    try {
      try {
        await _supabase
            .from('users')
            .update(profile.toMap())
            .eq('uid', user.id);
      } catch (e) {
        debugPrint('Failed to sync profile data: $e');
      }

      // Update Auth Display Name if changed
      if (profile.displayName != null && profile.displayName!.isNotEmpty) {
        await _supabase.auth.updateUser(
            UserAttributes(data: {'full_name': profile.displayName}));
      } else {
        await _supabase.auth
            .updateUser(UserAttributes(data: {'full_name': profile.fullName}));
      }
    } catch (e) {
      throw Exception('Profile update failed: $e');
    }
  }
}
