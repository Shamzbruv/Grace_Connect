import 'package:supabase_flutter/supabase_flutter.dart';
import 'tutorial_state.dart';

abstract class TutorialSync {
  Future<TutorialState> synchronize(String userId, TutorialState state);
}

class TutorialService implements TutorialSync {
  TutorialService(this.client);
  final SupabaseClient client;
  @override
  Future<TutorialState> synchronize(String userId, TutorialState state) async {
    if (client.auth.currentUser?.id != userId) {
      throw StateError('Tutorial account changed');
    }
    final result = await client.rpc('sync_user_tutorials', params: {
      'p_generation': state.generation,
      'p_enabled': state.enabled,
      'p_settings_dirty': state.settingsDirty,
      'p_progress': state.progressDirty
          ? state.progress.values
              .where((p) => p.generation == state.generation)
              .map((p) => p.toJson())
              .toList()
          : [],
    }).timeout(const Duration(seconds: 10));
    return TutorialState.fromJson(Map<String, dynamic>.from(result));
  }
}
