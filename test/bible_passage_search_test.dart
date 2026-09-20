import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/screens/bible/bible_search_delegate.dart';

void main() {
  group('BiblePassageSearch', () {
    test('resolves a full reference typed normally', () {
      final first = BiblePassageSearch.search('John 3:16').first;
      expect(first.book, 'John');
      expect(first.chapter, 3);
      expect(first.verse, 16);
      expect(first.label, 'John 3:16');
    });

    test('resolves abbreviations and a missing space', () {
      final abbreviated = BiblePassageSearch.search('jn3:16').first;
      expect(abbreviated.book, 'John');
      expect(abbreviated.chapter, 3);
      expect(abbreviated.verse, 16);

      final psalm = BiblePassageSearch.search('ps 23').first;
      expect(psalm.book, 'Psalms');
      expect(psalm.chapter, 23);
      expect(psalm.verse, isNull);
    });

    test('keeps a leading ordinal with the book name', () {
      final corinthians = BiblePassageSearch.search('1 cor 13').first;
      expect(corinthians.book, '1 Corinthians');
      expect(corinthians.chapter, 13);

      final timothy = BiblePassageSearch.search('2tim').first;
      expect(timothy.book, '2 Timothy');
    });

    test('a partial name without an ordinal offers every numbered book', () {
      final names =
          BiblePassageSearch.search('thess').map((s) => s.book).toList();
      expect(names, contains('1 Thessalonians'));
      expect(names, contains('2 Thessalonians'));
    });

    test('an exact prefix outranks a numbered book of the same name', () {
      expect(BiblePassageSearch.search('john').first.book, 'John');
    });

    test('a chapter past the end of the book does not navigate there', () {
      final result = BiblePassageSearch.search('Jude 5').first;
      expect(result.book, 'Jude');
      expect(result.chapter, isNull);
      expect(result.subtitle, contains('1 chapters'));
    });

    test('an unknown book returns nothing', () {
      expect(BiblePassageSearch.search('zzzz'), isEmpty);
    });

    test('an empty query returns nothing', () {
      expect(BiblePassageSearch.search('   '), isEmpty);
    });
  });
}
