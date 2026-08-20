import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Gemini is wired in as a second AI provider, tried only after Hugging '
      'Face fails, before any static fallback bank', () {
    final grace =
        File('supabase/functions/_shared/grace.ts').readAsStringSync();
    final quizGenerator = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();
    final motivationGenerator = File(
      'supabase/functions/generate-daily-motivation/index.ts',
    ).readAsStringSync();

    // A single Hugging Face outage (as happened in production) previously
    // meant no AI content at all -- the Bible Quiz's static fallback bank
    // only covers pop-quiz days, so a chapter-study day had no fallback at
    // all. Gemini closes that gap: callAiJson always tries Hugging Face
    // first (already tuned/prompted against in production) and only calls
    // Gemini when Hugging Face fails, for both scripture-grounded generators.
    expect(grace, contains('Deno.env.get("GEMINI_API_KEY")'));
    expect(grace, isNot(contains('Default Gemini API Key')));
    expect(grace, isNot(contains('Gemini projects/')));
    expect(grace, contains('export async function callGeminiJson('));
    expect(grace, contains('export async function callAiJson('));
    expect(
      grace,
      contains('const primary = await callHuggingFaceJson('),
    );
    expect(
      grace,
      contains('secondary = await callGeminiJson('),
    );

    // Both quiz generation and Daily Word generation must go through the
    // fallback-aware wrapper, not call Hugging Face directly -- otherwise
    // Gemini would only cover whichever generator was updated.
    expect(quizGenerator, contains('callAiJson'));
    expect(quizGenerator, isNot(contains('callHuggingFaceJson')));
    expect(motivationGenerator, contains('callAiJson'));
    expect(motivationGenerator, isNot(contains('callHuggingFaceJson')));

    // The static curated question bank is the last resort, not a second
    // option -- it must never be consulted before both AI providers have
    // already been given a chance to answer.
    expect(
      quizGenerator,
      contains('...(requiredChapterKey ? [] : fallbackQuizQuestions)'),
    );
  });
}
