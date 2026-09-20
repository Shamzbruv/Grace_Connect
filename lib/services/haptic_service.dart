import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide haptics, honouring the Settings switch.
///
/// The preference already existed and saved correctly -- nothing ever read
/// it, so turning haptics on did nothing anywhere in the app. This is the
/// missing half.
///
/// The value is cached in memory because feedback has to fire on the same
/// frame as the tap; awaiting SharedPreferences on every press would make
/// the buzz arrive late enough to feel disconnected from the touch.
class HapticService {
  HapticService._();

  static bool _enabled = true;
  static bool _loaded = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Two taps closer together than this feel like one long buzz rather than
  /// two responses, so the second is dropped.
  static const Duration _minimumGap = Duration(milliseconds: 60);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('haptics_enabled') ?? true;
      _loaded = true;
    } catch (error) {
      debugPrint('Haptic preference unavailable: $error');
      _loaded = true;
    }
  }

  /// Called by Settings so the change applies immediately rather than after
  /// the next restart.
  static void setEnabled(bool value) => _enabled = value;

  static bool get isEnabled => _enabled;

  static bool _allow() {
    if (!_enabled || !_loaded) return _enabled && _loaded;
    final now = DateTime.now();
    if (now.difference(_last) < _minimumGap) return false;
    _last = now;
    return true;
  }

  /// Moving between options: tab switches, toggles, selection changes.
  static void selection() {
    if (!_allow()) return;
    HapticFeedback.selectionClick();
  }

  /// A deliberate action completed: like, save, send, post.
  static void light() {
    if (!_allow()) return;
    HapticFeedback.lightImpact();
  }

  /// Something notable: check-in confirmed, upload finished.
  static void success() {
    if (!_allow()) return;
    HapticFeedback.mediumImpact();
  }

  /// A refusal or error the member should feel, not just read.
  static void warning() {
    if (!_allow()) return;
    HapticFeedback.heavyImpact();
  }
}
