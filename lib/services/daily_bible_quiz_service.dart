import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_resilience.dart';

class DailyBibleQuizService {
  DailyBibleQuizService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> status({bool generateIfMissing = false}) async {
    final current = await _invoke('get-daily-bible-quiz-status');
    if (!generateIfMissing || current['available'] == true) return current;

    try {
      await _invoke('generate-daily-bible-quiz');
      return _invoke('get-daily-bible-quiz-status');
    } catch (_) {
      return current;
    }
  }

  Future<Map<String, dynamic>> start() => _invoke('start-daily-bible-quiz');

  Future<Map<String, dynamic>> heartbeat(String attemptId) => _invokeQuietly(
        'heartbeat-daily-bible-quiz',
        body: {'attempt_id': attemptId},
      );

  Future<Map<String, dynamic>> abandon(String attemptId) => _invokeQuietly(
        'abandon-daily-bible-quiz',
        body: {'attempt_id': attemptId},
      );

  Future<Map<String, dynamic>> submitAnswer({
    required String attemptId,
    required String questionId,
    required int selectedOptionIndex,
  }) =>
      _invoke(
        'submit-daily-bible-quiz-answer',
        body: {
          'attempt_id': attemptId,
          'question_id': questionId,
          'selected_option_index': selectedOptionIndex,
          // New clients activate the next question only after the feedback
          // screen. Older Play Store builds omit this and retain legacy timing.
          'defer_next_question_start': true,
        },
      );

  Future<Map<String, dynamic>> leaderboard({String? quizMonth}) =>
      _invoke('get-church-quiz-leaderboard', body: {
        if (quizMonth != null) 'quiz_month': quizMonth,
      });

  Future<Map<String, dynamic>> _invoke(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _client.functions
          .invoke(
            functionName,
            body: body ?? const {},
          )
          .timeout(const Duration(seconds: 18));
      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] != null) throw Exception(map['error']);
        return map;
      }
    } catch (error, stackTrace) {
      if (SupabaseResilience.isTransientNetworkError(error)) {
        SupabaseResilience.logTransientNetworkError(
          'Daily Bible Quiz $functionName',
          error,
          stackTrace,
        );
      }
      rethrow;
    }
    throw Exception('Unexpected response from quiz service.');
  }

  Future<Map<String, dynamic>> _invokeQuietly(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await _invoke(functionName, body: body);
    } catch (error) {
      if (SupabaseResilience.isTransientNetworkError(error)) {
        return {'ok': false, 'offline': true};
      }
      rethrow;
    }
  }
}
