import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Daily Word permanently reserves chapters and rejects recycled wording',
      () {
    final migration = File(
      'supabase/migrations/20260814170000_daily_word_chapter_study_quiz.sql',
    ).readAsStringSync();
    final generator = File(
      'supabase/functions/generate-daily-motivation/index.ts',
    ).readAsStringSync();

    expect(migration, contains('daily_word_chapter_history'));
    expect(migration, contains('daily_word_content_history'));
    expect(migration, contains('chapter_key text primary key'));
    expect(migration, contains('trg_enforce_daily_word_unique_content'));
    expect(migration, contains('That Bible chapter has already been used'));
    expect(
        migration, contains('That Daily Word wording has already been used'));
    expect(generator, contains('wordSetSimilarity'));
    expect(generator, contains('>= 0.68'));
    expect(generator, contains('shuffledBibleChapters'));
    expect(generator, contains('usedChapterOwners'));
    expect(generator, contains('.from("daily_word_content_history")'));
    expect(generator, isNot(contains('fallbackMotivations')));
  });

  test('Monday Wednesday Saturday quizzes are locked to the Daily Word chapter',
      () {
    final migration = File(
      'supabase/migrations/20260814170000_daily_word_chapter_study_quiz.sql',
    ).readAsStringSync();
    final quizGenerator = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();

    expect(migration, contains("quiz_mode in ('pop_quiz', 'chapter_study')"));
    expect(migration,
        contains('Monday, Wednesday, and Saturday quizzes must use'));
    expect(
        migration, contains('Every chapter-study quiz reference must belong'));
    expect(migration, contains('source_daily_motivation_id'));
    expect(migration, contains("'daily-word-evening-preparation'"));
    expect(migration, contains("'daily-quiz-evening-preparation'"));
    expect(quizGenerator, contains('isChapterStudyDate(quizDate)'));
    expect(quizGenerator, contains('dailyWordStudyContext'));
    expect(quizGenerator, contains('requiredChapterKey'));
    expect(quizGenerator,
        contains('Every question and every scripture reference MUST'));
  });

  test('study notice opens the full chapter and is outside the shared image',
      () {
    final screen = File(
      'lib/screens/daily_word/daily_word_screen.dart',
    ).readAsStringSync();
    final repaint = screen.indexOf('RepaintBoundary(');
    final notice = screen.indexOf('_QuizStudyNotice(', repaint);
    final shareButton = screen.indexOf('Share Daily Word', repaint);

    expect(repaint, greaterThanOrEqualTo(0));
    expect(notice, greaterThan(repaint));
    expect(shareButton, greaterThan(notice));
    expect(screen, contains('All five questions are based on'));
    expect(screen, contains('book: passage.book'));
    expect(screen, contains('chapter: passage.chapter'));
  });

  test('developers can replace both scheduled items without moving the slot',
      () {
    final service =
        File('lib/services/developer_service.dart').readAsStringSync();
    final console = File(
      'lib/screens/developer/developer_console_screen.dart',
    ).readAsStringSync();
    final dailyGenerator = File(
      'supabase/functions/generate-daily-motivation/index.ts',
    ).readAsStringSync();

    expect(service, contains('regenerateScheduledDailyWord'));
    expect(service, contains("'regenerate_scheduled'"));
    expect(console, contains('_canReplaceScheduledDailyWord'));
    expect(console, contains('release time and study chapter were kept'));
    expect(dailyGenerator, contains('canRegenerateScheduledContent'));
    expect(dailyGenerator,
        contains('Only a future scheduled Daily Word can be refreshed'));
  });
}
