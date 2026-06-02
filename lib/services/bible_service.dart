import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BibleReference {
  final String text;
  final String bookName;
  final int chapter;
  final int verse;

  BibleReference({
    required this.text,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  factory BibleReference.fromJson(Map<String, dynamic> json) {
    return BibleReference(
      text: json['text'] ?? '',
      bookName: json['book_name'] ?? '',
      chapter: json['chapter'] ?? 0,
      verse: json['verse'] ?? 0,
    );
  }
}

class BibleService {
  static const String _baseUrl = 'https://bible-api.com';
  static const Duration _timeout = Duration(seconds: 12);

  /// Fetches a specific chapter e.g. "John 3"
  /// Returns a map with 'reference' (String), 'text' (String), 'verses' (List)
  Future<Map<String, dynamic>> getChapter(String book, int chapter) async {
    final query = '$book $chapter';
    return _fetchWithFallback(query, isChapter: true);
  }

  /// Search or get specific verse e.g. "John 3:16"
  Future<Map<String, dynamic>> getPassage(String reference) async {
    return _fetchWithFallback(reference, isChapter: false);
  }

  Future<Map<String, dynamic>> _fetchWithFallback(
    String reference, {
    required bool isChapter,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final preferredTranslation = prefs.getString('bible_translation') ?? 'web';
    final translations = <String>[
      preferredTranslation,
      if (preferredTranslation != 'web') 'web',
      '',
    ];

    Object? lastError;
    for (final translation in translations) {
      try {
        final response =
            await http.get(_buildUri(reference, translation)).timeout(_timeout);

        if (response.statusCode == 200) {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic>) {
            return _normalizePassageData(decoded, reference);
          }
        }

        lastError = 'Status ${response.statusCode}: ${response.body}';
      } catch (error) {
        lastError = error;
      }
    }

    final local = isChapter ? _localChapterFallback(reference) : null;
    if (local != null) return local;

    throw Exception('Error fetching passage: $lastError');
  }

  Map<String, dynamic> _normalizePassageData(
    Map<String, dynamic> data,
    String fallbackReference,
  ) {
    final verses = data['verses'];
    if (verses is List && verses.isNotEmpty) {
      return data;
    }

    final text = data['text']?.toString().trim() ?? '';
    final lines = text
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return {
        ...data,
        'reference': data['reference'] ?? fallbackReference,
        'verses': const [],
      };
    }

    return {
      ...data,
      'reference': data['reference'] ?? fallbackReference,
      'verses': [
        for (var i = 0; i < lines.length; i++)
          {
            'verse': i + 1,
            'text': lines[i],
          },
      ],
    };
  }

  Map<String, dynamic>? _localChapterFallback(String reference) {
    final normalized = reference.trim().toLowerCase();
    if (normalized == 'psalms 23' || normalized == 'psalm 23') {
      const verses = [
        'Yahweh is my shepherd: I shall lack nothing.',
        'He makes me lie down in green pastures. He leads me beside still waters.',
        'He restores my soul. He guides me in the paths of righteousness for his name\'s sake.',
        'Even though I walk through the valley of the shadow of death, I will fear no evil, for you are with me. Your rod and your staff, they comfort me.',
        'You prepare a table before me in the presence of my enemies. You anoint my head with oil. My cup runs over.',
        'Surely goodness and loving kindness shall follow me all the days of my life, and I will dwell in Yahweh\'s house forever.',
      ];

      return {
        'reference': 'Psalm 23',
        'translation_name': 'World English Bible',
        'verses': [
          for (var i = 0; i < verses.length; i++)
            {'verse': i + 1, 'text': verses[i]},
        ],
        'text': verses.join('\n'),
      };
    }

    if (normalized == 'john 3') {
      const verses = [
        'Now there was a man of the Pharisees named Nicodemus, a ruler of the Jews.',
        'He came to Jesus by night and said to him, "Rabbi, we know that you are a teacher come from God, for no one can do these signs that you do unless God is with him."',
        'Jesus answered him, "Most certainly, I tell you, unless one is born anew, he can\'t see God\'s Kingdom."',
        'Nicodemus said to him, "How can a man be born when he is old? Can he enter a second time into his mother\'s womb and be born?"',
        'Jesus answered, "Most certainly I tell you, unless one is born of water and spirit, he can\'t enter into God\'s Kingdom."',
        'That which is born of the flesh is flesh. That which is born of the Spirit is spirit.',
        'Don\'t marvel that I said to you, "You must be born anew."',
        'The wind blows where it wants to, and you hear its sound, but don\'t know where it comes from and where it is going. So is everyone who is born of the Spirit.',
        'Nicodemus answered him, "How can these things be?"',
        'Jesus answered him, "Are you the teacher of Israel, and don\'t understand these things?"',
        'Most certainly I tell you, we speak that which we know and testify of that which we have seen, and you don\'t receive our witness.',
        'If I told you earthly things and you don\'t believe, how will you believe if I tell you heavenly things?',
        'No one has ascended into heaven but he who descended out of heaven, the Son of Man, who is in heaven.',
        'As Moses lifted up the serpent in the wilderness, even so must the Son of Man be lifted up,',
        'that whoever believes in him should not perish, but have eternal life.',
        'For God so loved the world that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.',
      ];

      return {
        'reference': 'John 3',
        'translation_name': 'World English Bible',
        'verses': [
          for (var i = 0; i < verses.length; i++)
            {'verse': i + 1, 'text': verses[i]},
        ],
        'text': verses.join('\n'),
      };
    }

    return null;
  }

  Uri _buildUri(String reference, String translation) {
    final queryParameters = <String, String>{};
    if (translation.trim().isNotEmpty) {
      queryParameters['translation'] = translation.trim();
    }

    return Uri.parse('$_baseUrl/${Uri.encodeComponent(reference)}').replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }
}
