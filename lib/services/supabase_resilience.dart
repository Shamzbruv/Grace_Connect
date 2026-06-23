import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseResilience {
  static bool isAuthSessionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('invalidjwttoken') ||
        (message.contains('jwt') && message.contains('expired')) ||
        message.contains('refresh token') ||
        message.contains('session_not_found');
  }

  static Future<bool> refreshSession({String context = 'Supabase'}) async {
    try {
      await Supabase.instance.client.auth.refreshSession();
      return true;
    } catch (error) {
      debugPrint('$context session refresh failed: $error');
      return false;
    }
  }

  static Stream<T> guardedStream<T>({
    required Future<T> Function() fetchInitial,
    required Stream<T> Function() subscribe,
    Duration quietTimeout = const Duration(seconds: 18),
    String debugLabel = 'Realtime',
    bool yieldEmptyOnInitialFailure = false,
    T? emptyValue,
  }) async* {
    T? lastKnown;

    try {
      final initial = await fetchInitial();
      lastKnown = initial;
      yield initial;
    } catch (error) {
      debugPrint('$debugLabel initial load failed: $error');
      if (isAuthSessionError(error) &&
          await refreshSession(context: debugLabel)) {
        try {
          final retry = await fetchInitial();
          lastKnown = retry;
          yield retry;
        } catch (retryError) {
          debugPrint('$debugLabel retry load failed: $retryError');
        }
      }
      if (lastKnown == null &&
          yieldEmptyOnInitialFailure &&
          emptyValue != null) {
        yield emptyValue;
      }
    }

    try {
      await for (final value in subscribe().timeout(
        quietTimeout,
        onTimeout: (sink) {
          if (lastKnown != null) sink.add(lastKnown as T);
        },
      )) {
        lastKnown = value;
        yield value;
      }
    } catch (error) {
      debugPrint('$debugLabel realtime unavailable: $error');
      if (isAuthSessionError(error) &&
          await refreshSession(context: debugLabel)) {
        try {
          final refreshed = await fetchInitial();
          lastKnown = refreshed;
          yield refreshed;
        } catch (retryError) {
          debugPrint('$debugLabel post-refresh load failed: $retryError');
        }
      }
      if (lastKnown != null) {
        yield lastKnown as T;
      } else if (yieldEmptyOnInitialFailure && emptyValue != null) {
        yield emptyValue;
      }
    }
  }
}
