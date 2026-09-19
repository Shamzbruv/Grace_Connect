import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import '../models/reel.dart';

/// Reel Grace behavioural analytics.
///
/// These fire per playback, many times per session, which is exactly the
/// volume that should not become a Supabase write each. Firebase absorbs it;
/// Postgres keeps only durable social state (likes, comments, saves).
///
/// Nothing identifying is sent: no email, phone, caption text, church
/// membership or profile attributes -- only the reel id, its category, and
/// timing.
class ReelAnalytics {
  ReelAnalytics._();

  static FirebaseAnalytics? _analytics;

  static FirebaseAnalytics? get _instance {
    try {
      return _analytics ??= FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  static void _log(String name, Map<String, Object?> parameters) {
    final analytics = _instance;
    if (analytics == null) return;
    final clean = <String, Object>{};
    parameters.forEach((key, value) {
      if (value != null) clean[key] = value;
    });
    analytics.logEvent(name: name, parameters: clean).catchError((Object error) {
      debugPrint('Reel analytics failed: $error');
    });
  }

  static void impression(Reel reel, {required int position, required String feedMode}) =>
      _log('reel_impression', {
        'reel_id': reel.id,
        'category': reel.category ?? 'other',
        'position': position,
        'feed_mode': feedMode,
        'duration_ms': reel.durationMs,
      });

  static void play(Reel reel) =>
      _log('reel_play', {'reel_id': reel.id, 'category': reel.category ?? 'other'});

  /// label is one of 3s, 25, 50, 75 -- each fires once per playback.
  static void progress(Reel reel, String label, {required Duration position}) {
    const names = {
      '3s': 'reel_3s_view',
      '25': 'reel_25_pct',
      '50': 'reel_50_pct',
      '75': 'reel_75_pct',
    };
    final name = names[label];
    if (name == null) return;
    _log(name, {
      'reel_id': reel.id,
      'category': reel.category ?? 'other',
      'watch_ms': position.inMilliseconds,
    });
  }

  static void complete(Reel reel) => _log('reel_complete', {
        'reel_id': reel.id,
        'category': reel.category ?? 'other',
        'duration_ms': reel.durationMs,
      });

  static void replay(Reel reel) => _log('reel_replay', {'reel_id': reel.id});

  static void skip(Reel reel, {required Duration watched}) => _log('reel_skip', {
        'reel_id': reel.id,
        'category': reel.category ?? 'other',
        'watch_ms': watched.inMilliseconds,
      });

  static void like(Reel reel, {required bool liked}) =>
      _log(liked ? 'reel_like' : 'reel_unlike', {'reel_id': reel.id});

  static void save(Reel reel, {required bool saved}) =>
      _log('reel_save', {'reel_id': reel.id, 'saved': saved});

  static void share(Reel reel) => _log('reel_share', {'reel_id': reel.id});

  static void commentOpen(Reel reel) => _log('reel_comment_open', {'reel_id': reel.id});

  static void profileOpen(Reel reel) => _log('reel_profile_open', {'reel_id': reel.id});

  static void uploadStarted() => _log('reel_upload_started', const {});
  static void uploadCompleted({required int bytes, required int durationMs}) =>
      _log('reel_upload_completed', {'bytes': bytes, 'duration_ms': durationMs});
  static void uploadFailed(String stage) => _log('reel_upload_failed', {'stage': stage});
}
