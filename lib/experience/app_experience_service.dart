import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ExperienceBackend {
  Future<Map<String, dynamic>> sync(String userId, String deviceId, int seconds,
      {Map<String, dynamic>? event});
}

class AppExperienceService implements ExperienceBackend {
  AppExperienceService(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> sync(String userId, String deviceId, int seconds,
      {Map<String, dynamic>? event}) async {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Account changed');
    }
    final data = await client.rpc('sync_app_experience', params: {
      'p_device_id': deviceId,
      'p_active_seconds': seconds,
      'p_action': event?['kind'] ?? 'sync',
      'p_event_id': event?['id'],
      'p_response': event?['response'],
      'p_platform': event?['platform'],
    }).timeout(const Duration(seconds: 12));
    return Map<String, dynamic>.from(data as Map);
  }
}
