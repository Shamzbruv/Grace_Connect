import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily content notification claims are retryable and idempotent', () {
    final migration = File(
      'supabase/migrations/20260811120000_daily_content_notification_delivery_retry.sql',
    ).readAsStringSync();
    final motivation = File(
      'supabase/functions/generate-daily-motivation/index.ts',
    ).readAsStringSync();
    final quiz = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();
    final shared = File(
      'supabase/functions/_shared/grace.ts',
    ).readAsStringSync();

    expect(migration, contains('notification_claimed_at timestamptz'));
    expect(migration, contains("'daily-motivation-delivery-retry'"));
    expect(migration, contains("'daily-bible-quiz-delivery-retry'"));

    for (final source in [motivation, quiz]) {
      expect(source, contains('notification_claimed_at: claimedAt'));
      expect(source, contains('notification_claimed_at: null'));
      expect(
          source, contains('notification_sent_at: new Date().toISOString()'));
      expect(source, contains('Date.now() - 10 * 60 * 1000'));
    }

    expect(shared, contains('Push was already delivered.'));
    expect(shared, contains('.eq("status", "sent")'));
    expect(shared, contains('existingUserIds.has(row.user_id)'));
  });
}
