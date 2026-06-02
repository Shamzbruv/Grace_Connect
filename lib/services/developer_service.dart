
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';

class DeveloperService {

  final SupabaseClient _supabase = Supabase.instance.client;

  // Verify caller is a developer
  Future<bool> _checkDeveloperPermission() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    final doc = await _supabase.from('users').select().eq('uid', user.id).maybeSingle();
    if (doc == null) return false;

    final profile = UserProfile.fromMap(doc);
    return profile.isDeveloper;
  }

  // 1. Get Platform Stats
  Future<Map<String, dynamic>> getPlatformStats() async {
    if (!await _checkDeveloperPermission()) throw Exception('Access Denied');

    // Note: aggregations should be used for scalability, but for MVP counting snapshots is ok
    final usersRes = await _supabase.from('users').select('uid').count(CountOption.exact);
    final churchesRes = await _supabase.from('church_locations').select('id').count(CountOption.exact);

    return {
      'totalUsers': usersRes.count,
      'totalChurches': churchesRes.count,
      'serverHealth': 'Healthy', // Mock placeholder
    };
  }

  // 2. Fetch All Churches
  Future<List<Map<String, dynamic>>> getAllChurches() async {
    if (!await _checkDeveloperPermission()) throw Exception('Access Denied');

    final snapshot = await _supabase.from('church_locations').select();
    return snapshot.map((doc) => doc).toList();
  }

  // 3. Global User Search
  Future<List<UserProfile>> searchUsersGlobal(String email) async {
    if (!await _checkDeveloperPermission()) throw Exception('Access Denied');

    final snapshot = await _supabase
        .from('users')
        .select()
        .ilike('email', '%$email%')
        .limit(10);

    return snapshot.map((doc) => UserProfile.fromMap(doc)).toList();
  }
}
