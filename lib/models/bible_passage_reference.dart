import 'bible_data.dart';

class BiblePassageReference {
  const BiblePassageReference({
    required this.book,
    required this.chapter,
    required this.startVerse,
    this.endVerse,
  });

  final BibleBook book;
  final int chapter;
  final int startVerse;
  final int? endVerse;

  static BiblePassageReference? tryParse(String value) {
    // Generated copy can contain nonbreaking spaces/hyphens and other
    // typographic dashes. Normalize them before interpreting the reference.
    final normalized = value
        .replaceAll(RegExp(r'[\u2010-\u2015\u2212\uFE58\uFE63\uFF0D]'), '-')
        .replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ')
        .replaceAll(RegExp(r'[\u200B\uFEFF]'), '')
        .trim();
    final match = RegExp(
      r'^\s*([1-3]?\s*[A-Za-z]+(?:\s+[A-Za-z]+)*)\s+(\d{1,3}):(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?(?:\s*(?:\([^)]*\)|\[[^\]]*\]|[,;].*))?\s*$',
    ).firstMatch(normalized);
    if (match == null) return null;

    final requestedBook = _canonicalBookName(match.group(1)!);
    BibleBook? book;
    for (final candidate in BibleData.allBooks) {
      if (_canonicalBookName(candidate.name) == requestedBook) {
        book = candidate;
        break;
      }
    }
    final chapter = int.tryParse(match.group(2)!);
    final startVerse = int.tryParse(match.group(3)!);
    final endVerse = int.tryParse(match.group(4) ?? '');
    if (book == null ||
        chapter == null ||
        chapter < 1 ||
        chapter > book.chapters ||
        startVerse == null ||
        startVerse < 1 ||
        (endVerse != null && endVerse < startVerse)) {
      return null;
    }
    return BiblePassageReference(
      book: book,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
    );
  }

  /// Chapter metadata has no verse suffix; open it at verse one.
  static BiblePassageReference? tryParseChapter(String value) {
    return tryParse('${value.trim()}:1');
  }

  static String _canonicalBookName(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    switch (normalized) {
      case 'psalm':
      case 'psalms':
        return 'psalms';
      case 'song of songs':
      case 'canticles':
        return 'song of solomon';
      case 'revelations':
        return 'revelation';
      default:
        return normalized;
    }
  }
}
