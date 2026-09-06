import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/bible_passage_reference.dart';

void main() {
  test('opens the typography used by published Daily Word references', () {
    for (final dash in ['-', '‐', '‑', '‒', '–', '—', '−']) {
      final passage = BiblePassageReference.tryParse('Psalm\u00a099:1${dash}2');
      expect(passage?.book.name, 'Psalms');
      expect(passage?.chapter, 99);
      expect(passage?.endVerse, 2);
    }
    expect(BiblePassageReference.tryParse('Job 36:27‑30')?.endVerse, 30);
    expect(BiblePassageReference.tryParseChapter('psalms 99')?.chapter, 99);
  });
  test('parses a Daily Word verse and range into the local Bible reader', () {
    final single = BiblePassageReference.tryParse('Ephesians 4:29');
    expect(single, isNotNull);
    expect(single!.book.name, 'Ephesians');
    expect(single.chapter, 4);
    expect(single.startVerse, 29);
    expect(single.endVerse, isNull);

    final range = BiblePassageReference.tryParse('Philippians 4:6-7');
    expect(range, isNotNull);
    expect(range!.book.name, 'Philippians');
    expect(range.chapter, 4);
    expect(range.startVerse, 6);
    expect(range.endVerse, 7);

    final translated = BiblePassageReference.tryParse('John 3:16 (NIV)');
    expect(translated, isNotNull);
    expect(translated!.book.name, 'John');
    expect(translated.chapter, 3);
    expect(translated.startVerse, 16);

    final multiple = BiblePassageReference.tryParse('John 3:16; 17:3');
    expect(multiple, isNotNull);
    expect(multiple!.startVerse, 16);
  });

  test('normalizes common book aliases and rejects invalid chapters', () {
    expect(
      BiblePassageReference.tryParse('Psalm 119:105')?.book.name,
      'Psalms',
    );
    expect(
      BiblePassageReference.tryParse('Song of Songs 2:1')?.book.name,
      'Song of Solomon',
    );
    expect(BiblePassageReference.tryParse('Ephesians 99:1'), isNull);
    expect(BiblePassageReference.tryParse('not a verse'), isNull);
  });
}
