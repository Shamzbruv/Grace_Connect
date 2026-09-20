import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// App-wide analytics.
///
/// Reel Grace has its own high-volume service; this one covers everything
/// else — which screens people reach, and the handful of moments that say
/// whether the app is doing its job (a quiz finished, a streak kept, a verse
/// shared, a subscription started).
///
/// Nothing identifying is ever sent: no name, email, phone, church id,
/// message text, prayer text, or scripture content. Events carry categories
/// and counts, not people. Analytics is also strictly best-effort — every
/// call swallows its own failure, because a metric must never be the reason
/// a member cannot finish what they were doing.
class Analytics {
  Analytics._();

  static FirebaseAnalytics? _analytics;

  static FirebaseAnalytics? get instance {
    try {
      return _analytics ??= FirebaseAnalytics.instance;
    } catch (_) {
      // Firebase is not initialised in tests, and on a device that failed to
      // initialise it we would rather lose the metric than crash the app.
      return null;
    }
  }

  /// Attach to MaterialApp.navigatorObservers for automatic screen tracking.
  static FirebaseAnalyticsObserver? get observer {
    final analytics = instance;
    if (analytics == null) return null;
    return FirebaseAnalyticsObserver(analytics: analytics);
  }

  static void log(String name, [Map<String, Object?> parameters = const {}]) {
    final analytics = instance;
    if (analytics == null) return;
    final clean = <String, Object>{};
    parameters.forEach((key, value) {
      if (value != null) clean[key] = value;
    });
    analytics.logEvent(name: name, parameters: clean).catchError((Object error) {
      debugPrint('Analytics failed ($name): $error');
    });
  }

  // --- Sessions -------------------------------------------------------

  static void appOpened() => log('app_opened');

  static void signedIn(String method) => log('login', {'method': method});

  static void signedUp(String method) => log('sign_up', {'method': method});

  // --- Bible ----------------------------------------------------------

  static void bibleChapterOpened(String book, int chapter) =>
      log('bible_chapter_opened', {'book': book, 'chapter': chapter});

  static void bibleSearched({required bool foundMatch}) =>
      log('bible_searched', {'found_match': foundMatch});

  /// The query itself is deliberately not sent. What people search for in a
  /// Bible can be deeply personal, and the useful signal is whether the
  /// search worked, not what was typed.
  static void bibleSearchResultOpened() => log('bible_search_result_opened');

  static void bibleStreakExtended(int streakDays) =>
      log('bible_streak_extended', {'streak_days': streakDays});

  // --- Quiz -----------------------------------------------------------

  static void quizStarted() => log('quiz_started');

  static void quizCompleted({required int score, required int total}) =>
      log('quiz_completed', {'score': score, 'total': total});

  static void leaderboardViewed(String scope) =>
      log('leaderboard_viewed', {'scope': scope});

  // --- Sharing --------------------------------------------------------

  static void contentShared(String contentType) =>
      log('share', {'content_type': contentType});

  // --- Subscription ---------------------------------------------------

  static void subscriptionScreenViewed(String status) =>
      log('subscription_viewed', {'status': status});

  static void subscriptionCheckoutOpened() => log('subscription_checkout_opened');

  static void subscriptionManageOpened() => log('subscription_manage_opened');
}
