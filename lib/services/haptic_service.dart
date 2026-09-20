import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// App-wide haptics, honouring the Settings switch.
///
/// Two separate things were wrong. The preference saved correctly but nothing
/// ever read it, so the switch did nothing. And the feedback itself went
/// through [HapticFeedback], which on Android is routed through the system
/// "touch vibration" setting -- if that is off, every call is silently
/// discarded and the app feels identical either way.
///
/// So the motor is driven directly through the vibration plugin, with
/// [HapticFeedback] kept only as the fallback for devices with no amplitude
/// control (and for iOS, where the Taptic engine through HapticFeedback is
/// the better-feeling path).
///
/// The enabled flag is cached in memory because feedback has to fire on the
/// same frame as the tap; awaiting SharedPreferences on every press would
/// make the buzz arrive late enough to feel disconnected from the touch.
class HapticService {
  HapticService._();

  static bool _enabled = true;
  static bool _loaded = false;
  static bool _hasVibrator = false;
  static bool _hasAmplitude = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Two taps closer together than this feel like one long buzz rather than
  /// two responses, so the second is dropped.
  static const Duration _minimumGap = Duration(milliseconds: 60);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('haptics_enabled') ?? true;
    } catch (error) {
      debugPrint('Haptic preference unavailable: $error');
    }
    // Probed once at startup: asking the platform on every tap would add a
    // channel round trip to the one code path that must not be delayed.
    try {
      _hasVibrator = await Vibration.hasVibrator();
      if (_hasVibrator) {
        _hasAmplitude = await Vibration.hasAmplitudeControl();
      }
    } catch (error) {
      debugPrint('Vibration capability unavailable: $error');
      _hasVibrator = false;
    }
    _loaded = true;
  }

  /// Called by Settings so the change applies immediately rather than after
  /// the next restart.
  static void setEnabled(bool value) => _enabled = value;

  static bool get isEnabled => _enabled;

  /// Whether this device can actually produce feedback, so Settings can say
  /// so instead of offering a switch that cannot do anything.
  static bool get isSupported => _hasVibrator;

  static bool _allow() {
    if (!_enabled || !_loaded) return false;
    final now = DateTime.now();
    if (now.difference(_last) < _minimumGap) return false;
    _last = now;
    return true;
  }

  /// Drives the motor for [ms] at [amplitude] (1-255), falling back to the
  /// platform haptic when the device has no amplitude control.
  static void _buzz(int ms, int amplitude, void Function() fallback) {
    if (!_hasVibrator) {
      fallback();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS's Taptic engine through HapticFeedback feels far better than a
      // raw duration, and iOS ignores amplitude anyway.
      fallback();
      return;
    }
    try {
      Vibration.vibrate(
        duration: ms,
        amplitude: _hasAmplitude ? amplitude : -1,
      );
    } catch (error) {
      debugPrint('Vibration failed: $error');
      fallback();
    }
  }

  /// Moving between options: tab switches, toggles, selection changes.
  static void selection() {
    if (!_allow()) return;
    _buzz(12, 90, HapticFeedback.selectionClick);
  }

  /// A deliberate action completed: like, save, send, post.
  static void light() {
    if (!_allow()) return;
    _buzz(20, 140, HapticFeedback.lightImpact);
  }

  /// Something notable: check-in confirmed, upload finished.
  static void success() {
    if (!_allow()) return;
    _buzz(35, 200, HapticFeedback.mediumImpact);
  }

  /// A refusal or error the member should feel, not just read.
  static void warning() {
    if (!_allow()) return;
    _buzz(60, 255, HapticFeedback.heavyImpact);
  }

  /// A distinct double pulse used by the Settings test button, so "is this
  /// working?" has an unambiguous answer rather than a buzz so short it can
  /// be mistaken for nothing.
  static Future<void> test() async {
    _last = DateTime.fromMillisecondsSinceEpoch(0);
    if (!_hasVibrator) {
      HapticFeedback.heavyImpact();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      HapticFeedback.heavyImpact();
      return;
    }
    try {
      Vibration.vibrate(
        pattern: [0, 90, 110, 200],
        intensities: _hasAmplitude ? [0, 180, 0, 255] : const [],
      );
    } catch (error) {
      debugPrint('Vibration test failed: $error');
      HapticFeedback.heavyImpact();
    }
  }
}
