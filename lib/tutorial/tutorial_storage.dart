import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'tutorial_state.dart';

class TutorialStorage {
  String key(String userId) => 'tutorial.$userId.state.v1';
  Future<TutorialState> load(String userId) async {
    try {
      final value =
          (await SharedPreferences.getInstance()).getString(key(userId));
      return value == null
          ? TutorialState()
          : TutorialState.fromJson(jsonDecode(value));
    } catch (_) {
      return TutorialState();
    }
  }

  Future<void> save(String userId, TutorialState state) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(key(userId), jsonEncode(state.toJson()));
    } catch (_) {
      /* Guidance must never block the app when local storage fails. */
    }
  }
}
