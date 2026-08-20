import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict quiz selection never reintroduces blocked facts', () {
    final generator = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260811150000_strict_daily_quiz_uniqueness.sql',
    ).readAsStringSync();

    expect(generator, contains('canonicalQuizFactKeys'));
    expect(generator, contains('get_blocked_daily_bible_quiz_fact_keys'));
    expect(generator, contains('rotatingQuizFactExclusions'));
    expect(
      generator,
      contains('ensureSharedAiResponse(blockedFactKeys)'),
    );
    expect(generator, isNot(contains('allowBlockedFacts')));
    expect(
      generator,
      contains('fewer than five unseen Scripture facts are available'),
    );
    expect(
      generator,
      isNot(contains('fresh.length >= 5 ? fresh : annotated')),
    );

    expect(migration,
        contains('quiz_guarantee_unique boolean not null default true'));
    expect(
      migration,
      contains("q.status = 'scheduled' or q.first_published_at is not null"),
    );
    expect(migration, contains('add column if not exists first_published_at'));
    expect(
      migration,
      contains('new.first_published_at := old.first_published_at'),
    );
    expect(
      migration,
      contains('update of status, first_published_at'),
    );
    expect(
      migration,
      contains(
          'A quiz that has already been published cannot have its questions replaced'),
    );
    expect(migration, contains('qq.fact_keys && p_fact_keys'));
    expect(migration, contains("v_reference_key || 'person:jesus'"));
    expect(
      migration,
      contains("q.church_id in (p_church_id, 'grace_connect_global')"),
    );
    expect(
      migration,
      contains("q.church_id in (v_quiz.church_id, 'grace_connect_global')"),
    );
    expect(migration, contains('lock_daily_bible_quiz_audience'));
    expect(migration, contains('pg_advisory_xact_lock_shared'));
    expect(migration, contains("'daily-bible-quiz:audience:'"));
    expect(
      migration,
      contains('q.quiz_date >= v_quiz.quiz_date - v_relaxed_days'),
    );
    expect(migration, contains('q.quiz_date <= v_quiz.quiz_date'));
    expect(migration, contains('publish_daily_bible_quiz_if_unique'));
    expect(migration, contains('validate_daily_bible_quiz_uniqueness'));
    expect(
      migration,
      contains('trg_enforce_daily_bible_quiz_publish_uniqueness'),
    );
    expect(
      migration,
      contains(
          'revoke insert, update, delete on table public.daily_bible_quiz_questions'),
    );
    expect(
      migration,
      contains(
          'grant update (status) on table public.daily_bible_quizzes to authenticated'),
    );
    expect(
      migration,
      contains(
          'create policy "Admins update own church quiz publication status"'),
    );
    expect(migration, contains('for update\n  to authenticated'));
    expect(
      migration,
      isNot(contains(
          'grant insert, update, delete on table public.daily_bible_quiz_questions\n  to authenticated')),
    );
    expect(migration, contains('admin_set_daily_bible_quiz_published'));
    expect(
      migration,
      contains('Strict quiz uniqueness rejected a fact used by retained'),
    );
  });

  test('admin publication uses the database-guarded RPC', () {
    final admin = File(
      'lib/screens/admin/daily_bible_quiz_admin_screen.dart',
    ).readAsStringSync();
    expect(admin, contains("'admin_set_daily_bible_quiz_published'"));
    expect(
      admin,
      isNot(contains("from('daily_bible_quizzes').update")),
    );
  });

  test('developer contract exposes an on-by-default audited control', () {
    final migration = File(
      'supabase/migrations/20260811150000_strict_daily_quiz_uniqueness.sql',
    ).readAsStringSync();
    final console = File(
      'lib/screens/developer/developer_console_screen.dart',
    ).readAsStringSync();

    expect(migration, contains("'quiz_uniqueness_settings'"));
    expect(migration, contains("'strict_history_scope'"));
    expect(migration, contains("'all_retained_published_and_scheduled'"));
    expect(
      migration,
      contains('developer_update_quiz_uniqueness_settings'),
    );
    for (final role in const [
      'super_developer',
      'support_developer',
      'content_moderator',
      'security_admin',
    ]) {
      expect(migration, contains("'$role'"));
    }
    expect(console, contains('Guarantee different quiz facts'));
    expect(console, contains('If five unseen facts are unavailable'));
    expect(console, contains("quiz['church_name']"));
    expect(console, isNot(contains("quiz['church_id']")));
  });

  test('Daily Word verse opens the reader at its target verse', () {
    final dailyWord = File('lib/screens/daily_word/daily_word_screen.dart')
        .readAsStringSync();
    final reader =
        File('lib/screens/bible/bible_reader_screen.dart').readAsStringSync();

    expect(dailyWord, contains('BiblePassageReference.tryParse'));
    expect(dailyWord, contains('initialVerse: passage.startVerse'));
    expect(dailyWord,
        contains('Read \${motivation.scriptureReference} in context'));
    expect(reader, contains('final int? initialVerse'));
    expect(reader, contains('Scrollable.ensureVisible'));
    expect(reader, contains('isLinkedVerse'));
  });

  test(
      'chapter-study quiz uniqueness no longer competes with Global for the '
      'same chapter', () {
    final migration = File(
      'supabase/migrations/20260819235000_chapter_study_fact_isolation.sql',
    ).readAsStringSync();

    // On a chapter-study day every audience is deliberately assigned the
    // same linked chapter, so blocking a church's generation on facts
    // Global already picked from that identical chapter forces N audiences
    // to find 5*N mutually-exclusive facts out of one chapter -- this is
    // what was failing in production. Only an audience's own history should
    // block it on those days; pop-quiz days keep the original sharing.
    expect(
      migration,
      contains(
          'select coalesce(has_study_quiz, false) into v_chapter_study'),
    );
    expect(
      migration,
      contains(
          "q.church_id = p_church_id\n        or (not v_chapter_study and q.church_id = 'grace_connect_global')"),
    );
    expect(
      migration,
      contains("v_chapter_study := v_quiz.quiz_mode = 'chapter_study';"),
    );
    expect(
      migration,
      contains(
          "q.church_id = v_quiz.church_id\n        or (not v_chapter_study and q.church_id = 'grace_connect_global')"),
    );
    expect(migration, isNot(contains("in (p_church_id, 'grace_connect_global')")));
    expect(
      migration,
      isNot(contains("in (v_quiz.church_id, 'grace_connect_global')")),
    );
  });

  test(
      'quiz fact blocking never treats Global mirroring the same content to a '
      'church as a conflict', () {
    final migration = File(
      'supabase/migrations/20260820013000_retire_cross_audience_global_fact_blocking.sql',
    ).readAsStringSync();
    final generator = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();

    // Grace Connect Global and every church now always show the identical
    // quiz (one canonical generation, mirrored everywhere). The pop-quiz-day
    // rule that counted Global's own picked facts as blocking every church's
    // generation was written for the old per-audience-independent
    // architecture -- under mirroring it rejects every legitimate copy of
    // Global's quiz, because Global's facts always show up as "already
    // claimed by another audience". Confirmed in production for the
    // 2026-08-20 prepare cycle: every fact in Global's scheduled quiz
    // blocked the mirrored insert for a church that had never seen those
    // facts before. Blocking must be scoped to an audience's own retained
    // history only, with no cross-audience comparison against Global at all,
    // on every day type.
    expect(
      migration,
      contains('and q.church_id = p_church_id\n      and ('),
    );
    expect(
      migration,
      contains('and q.church_id = v_quiz.church_id\n      and ('),
    );
    expect(migration, isNot(contains('grace_connect_global')));
    expect(migration, isNot(contains('v_chapter_study')));

    expect(generator, contains('loadPublishedGlobalSelection'));
    expect(
      generator,
      contains('canonicalSelection = await loadPublishedGlobalSelection('),
    );
    expect(generator, contains('hasConflict = canonicalFactKeys.some('));
  });
}
