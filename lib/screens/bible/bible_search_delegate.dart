import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/bible_data.dart';
import '../../services/analytics_service.dart';
import '../../services/bible_service.dart';
import 'bible_chapters_screen.dart';
import 'bible_reader_screen.dart';

/// Find a passage by typing.
///
/// Suggestions update on every keystroke rather than behind a submit, because
/// somebody typing "jn 3:16" wants it in two keystrokes -- and when the typed
/// reference is complete enough to resolve to a verse, the verse text itself
/// is fetched and shown inline, so the search answers the question instead of
/// only pointing at where the answer lives.
class BibleSearchDelegate extends SearchDelegate<void> {
  BibleSearchDelegate() : super(searchFieldLabel: 'Search a book or reference');

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  // Enter shows the same list the member is already looking at. Swapping in a
  // different layout on submit would hide the suggestion they were reaching
  // for, and every row here is already a finished answer.
  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    return _BibleSuggestionsView(
      query: query,
      onExample: (example) {
        query = example;
      },
      onSelected: (suggestion) {
        Analytics.bibleSearchResultOpened();
        close(context, null);
        final book =
            BibleData.allBooks.firstWhere((b) => b.name == suggestion.book);
        if (suggestion.chapter == null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BibleChaptersScreen(book: book),
          ));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BibleReaderScreen(
            book: book,
            chapter: suggestion.chapter!,
            initialVerse: suggestion.verse,
          ),
        ));
      },
    );
  }
}

class _BibleSuggestionsView extends StatefulWidget {
  const _BibleSuggestionsView({
    required this.query,
    required this.onSelected,
    required this.onExample,
  });

  final String query;
  final ValueChanged<PassageSuggestion> onSelected;
  final ValueChanged<String> onExample;

  @override
  State<_BibleSuggestionsView> createState() => _BibleSuggestionsViewState();
}

class _BibleSuggestionsViewState extends State<_BibleSuggestionsView> {
  final BibleService _bibleService = BibleService();

  Timer? _debounce;
  String? _previewReference;
  String? _previewText;
  bool _previewLoading = false;

  /// Guards against a slow early request landing after a faster later one and
  /// painting the wrong verse under the current query.
  int _requestToken = 0;

  @override
  void didUpdateWidget(covariant _BibleSuggestionsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _schedulePreview();
  }

  @override
  void initState() {
    super.initState();
    _schedulePreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    final suggestions = BiblePassageSearch.search(widget.query);
    final target = suggestions.isNotEmpty ? suggestions.first : null;

    // Only a resolved verse is worth a network round trip; a bare book name
    // has nothing specific to preview.
    if (target == null || target.chapter == null || target.verse == null) {
      if (_previewReference != null || _previewLoading) {
        setState(() {
          _previewReference = null;
          _previewText = null;
          _previewLoading = false;
        });
      }
      return;
    }

    final reference = '${target.book} ${target.chapter}:${target.verse}';
    if (reference == _previewReference && _previewText != null) return;

    setState(() {
      _previewReference = reference;
      _previewText = null;
      _previewLoading = true;
    });

    // Typing "John 3:16" fires five usable references on the way through; a
    // debounce keeps the lookup to the one the member actually stopped on.
    final token = ++_requestToken;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final data = await _bibleService.getPassage(reference);
        if (!mounted || token != _requestToken) return;
        setState(() {
          _previewText = (data['text'] as String?)?.trim();
          _previewLoading = false;
        });
      } catch (_) {
        if (!mounted || token != _requestToken) return;
        // The row still navigates to the reader, so a failed preview is a
        // missing convenience rather than a dead end worth an error banner.
        setState(() {
          _previewText = null;
          _previewLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = widget.query.trim();

    if (trimmed.isEmpty) return _emptyState(theme);

    final suggestions = BiblePassageSearch.search(trimmed);
    if (suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'No book matches "$trimmed".\nTry "John 3:16", "Ps 23", or "1 Cor 13".',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    final first = suggestions.first;
    final showPreview = _previewReference != null &&
        first.chapter != null &&
        first.verse != null &&
        _previewReference == '${first.book} ${first.chapter}:${first.verse}';

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: suggestions.length + (showPreview ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (showPreview && index == 0) {
          return _previewCard(theme, first);
        }
        final suggestion = suggestions[index - (showPreview ? 1 : 0)];
        return ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(
            suggestion.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(suggestion.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => widget.onSelected(suggestion),
        );
      },
    );
  }

  Widget _previewCard(ThemeData theme, PassageSuggestion suggestion) {
    return InkWell(
      onTap: () => widget.onSelected(suggestion),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _previewReference!,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (_previewLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.chevron_right, color: theme.hintColor),
              ],
            ),
            const SizedBox(height: 8),
            if (_previewLoading)
              Text('Loading the verse…', style: theme.textTheme.bodySmall)
            else if (_previewText != null && _previewText!.isNotEmpty)
              Text(
                _previewText!,
                style: GoogleFonts.merriweather(fontSize: 15, height: 1.5),
              )
            else
              Text(
                'Tap to open this passage.',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Try a reference',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final example in const [
              'John 3:16',
              'Ps 23',
              'Rom 8:28',
              '1 Cor 13',
              'Phil 4:6',
            ])
              ActionChip(
                label: Text(example),
                onPressed: () => widget.onExample(example),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Short forms work too — "jn 3", "1thess", "rev 21:4".',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One row in the search results: a book, optionally narrowed to a chapter
/// and verse.
class PassageSuggestion {
  const PassageSuggestion({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.label,
    required this.subtitle,
  });

  final String book;
  final int? chapter;
  final int? verse;
  final String label;
  final String subtitle;
}

/// Turns whatever the member typed into passage suggestions.
///
/// Matching is deliberately forgiving -- abbreviations ("jn", "ps"), a missing
/// space ("1john"), and partial names ("thess") all resolve -- because people
/// do not type book names the way a catalogue spells them.
class BiblePassageSearch {
  const BiblePassageSearch._();

  static const Map<String, String> _aliases = {
    'gen': 'Genesis', 'ex': 'Exodus', 'exo': 'Exodus', 'lev': 'Leviticus',
    'num': 'Numbers', 'deut': 'Deuteronomy', 'dt': 'Deuteronomy',
    'josh': 'Joshua', 'judg': 'Judges', 'ps': 'Psalms', 'psalm': 'Psalms',
    'pss': 'Psalms', 'prov': 'Proverbs', 'pr': 'Proverbs',
    'eccl': 'Ecclesiastes', 'song': 'Song of Solomon', 'isa': 'Isaiah',
    'jer': 'Jeremiah', 'lam': 'Lamentations', 'ezek': 'Ezekiel',
    'dan': 'Daniel', 'hos': 'Hosea', 'mt': 'Matthew', 'matt': 'Matthew',
    'mk': 'Mark', 'mrk': 'Mark', 'lk': 'Luke', 'jn': 'John', 'joh': 'John',
    'rom': 'Romans', 'cor': 'Corinthians', 'gal': 'Galatians',
    'eph': 'Ephesians', 'phil': 'Philippians', 'col': 'Colossians',
    'thess': 'Thessalonians', 'tim': 'Timothy', 'tit': 'Titus',
    'heb': 'Hebrews', 'jas': 'James', 'pet': 'Peter', 'rev': 'Revelation',
    'apoc': 'Revelation',
  };

  static List<PassageSuggestion> search(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return const [];

    // Split a trailing "3:16" or "3" off the book name, tolerating a missing
    // space ("john3:16") which is how references get typed in a hurry.
    final match = RegExp(r'^(.*?)\s*(\d+)?\s*(?::\s*(\d+))?$').firstMatch(query);
    var bookPart = (match?.group(1) ?? query).trim();
    final chapter = int.tryParse(match?.group(2) ?? '');
    final verse = int.tryParse(match?.group(3) ?? '');

    // A leading ordinal ("1 john", "2tim") belongs to the book name, not to
    // the chapter.
    final ordinal = RegExp(r'^([123])\s*(.*)$').firstMatch(bookPart);
    String? ordinalPrefix;
    if (ordinal != null && (ordinal.group(2) ?? '').isNotEmpty) {
      ordinalPrefix = ordinal.group(1);
      bookPart = ordinal.group(2)!.trim();
    }

    final expanded = (_aliases[bookPart] ?? bookPart).toLowerCase();
    final needle =
        ordinalPrefix == null ? expanded : '$ordinalPrefix $expanded';

    final books = BibleData.allBooks.where((book) {
      final name = book.name.toLowerCase();
      if (name.startsWith(needle) || name.contains(needle)) return true;
      // "thess" should still find "1 Thessalonians" when no ordinal is typed.
      final withoutOrdinal = name.replaceFirst(RegExp(r'^[123]\s+'), '');
      return withoutOrdinal.startsWith(expanded);
    }).toList()
      // An exact-prefix hit is what was meant; "John" outranks "1 John".
      ..sort((a, b) {
        final aStarts = a.name.toLowerCase().startsWith(needle) ? 0 : 1;
        final bStarts = b.name.toLowerCase().startsWith(needle) ? 0 : 1;
        return aStarts.compareTo(bStarts);
      });

    final results = <PassageSuggestion>[];
    for (final book in books.take(12)) {
      if (chapter != null && chapter >= 1 && chapter <= book.chapters) {
        results.add(PassageSuggestion(
          book: book.name,
          chapter: chapter,
          verse: verse,
          label: verse == null
              ? '${book.name} $chapter'
              : '${book.name} $chapter:$verse',
          subtitle: '${book.testament} Testament · ${book.category}',
        ));
      } else if (chapter != null && chapter > book.chapters) {
        results.add(PassageSuggestion(
          book: book.name,
          chapter: null,
          verse: null,
          label: book.name,
          // Saying why is more use than silently opening a different chapter.
          subtitle: '${book.name} has ${book.chapters} chapters',
        ));
      } else {
        results.add(PassageSuggestion(
          book: book.name,
          chapter: null,
          verse: null,
          label: book.name,
          subtitle: '${book.chapters} chapters · ${book.testament} Testament',
        ));
      }
    }
    return results;
  }
}
