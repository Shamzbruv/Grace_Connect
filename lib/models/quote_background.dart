import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Public Supabase Storage bucket -- adding, replacing, or fixing a
// background is now an upload, not an app release. The bucket is public
// (no user data in these images, same trust level as the app icon already
// served from the bundle) and its catalogue_manifest.json is the same
// shape the app used to read out of assets/, just fetched over HTTP now.
const String _quoteBackgroundsBaseUrl =
    'https://nimgsgnkcvddomrgkawb.supabase.co/storage/v1/object/public/quote-backgrounds/quote_backgrounds';

/// One curated background served from Supabase Storage, described by
/// catalogue_manifest.json rather than hardcoded -- new backgrounds can be
/// added by uploading a PNG and a manifest entry, no app release needed.
class QuoteBackground {
  const QuoteBackground({
    required this.imageUrl,
    required this.title,
    required this.category,
    required this.recommendedTextColor,
    required this.safeTextArea,
  });

  final String imageUrl;
  final String title;
  final String category;
  final Color recommendedTextColor;
  final String safeTextArea;

  /// A row of the developer-managed `quote_backgrounds` table.
  factory QuoteBackground.fromRow(Map<String, dynamic> row) {
    return QuoteBackground(
      imageUrl: '$_quoteBackgroundsBaseUrl/${row['file_name']}',
      title: row['title']?.toString() ?? 'Background',
      category: row['category']?.toString() ?? '',
      recommendedTextColor:
          _parseColor(row['recommended_text_color']?.toString()),
      safeTextArea: row['safe_text_area']?.toString() ?? 'center',
    );
  }

  factory QuoteBackground.fromManifestEntry(Map<String, dynamic> entry) {
    return QuoteBackground(
      imageUrl: '$_quoteBackgroundsBaseUrl/${entry['file']}',
      title: entry['title']?.toString() ?? 'Background',
      category: entry['category']?.toString() ?? '',
      recommendedTextColor:
          _parseColor(entry['recommended_text_color']?.toString()),
      safeTextArea: entry['safe_text_area']?.toString() ?? 'center',
    );
  }

  static Color _parseColor(String? value) {
    if (value == null) return Colors.white;
    if (value.toLowerCase() == 'white') return Colors.white;
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return Colors.white;
    return Color(0xFF000000 | parsed);
  }
}

class QuoteBackgroundCatalogue {
  QuoteBackgroundCatalogue._();

  static List<QuoteBackground>? _cache;
  static DateTime? _loadedAt;

  /// The public URL of a catalogue image, so the developer screen and the
  /// share card resolve the same object from the same one place.
  static String publicUrlFor(String fileName) =>
      '$_quoteBackgroundsBaseUrl/$fileName';

  /// Drops the cache so a developer's change shows on the next open rather
  /// than after an app restart.
  static void invalidate() {
    _cache = null;
    _loadedAt = null;
  }

  static Future<List<QuoteBackground>> load() async {
    final cached = _cache;
    if (cached != null &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
      return cached;
    }

    // The catalogue is a table now, so a background added in the developer
    // screen appears on the next catalogue refresh. The legacy manifest is
    // used only when this environment has not installed the catalogue table.
    try {
      final rows = await Supabase.instance.client
          .from('quote_backgrounds')
          .select()
          .eq('is_active', true)
          .order('sort_order')
          .order('created_at');
      final entries = (rows as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(QuoteBackground.fromRow)
          .toList(growable: false);
      // An empty catalogue is intentional (all backgrounds may be disabled).
      // Do not resurrect removed backgrounds from the legacy manifest.
      _cache = entries;
      _loadedAt = DateTime.now();
      return entries;
    } on PostgrestException catch (error) {
      if (!{'42P01', 'PGRST205'}.contains(error.code)) rethrow;
      // Compatibility only for deployments predating the catalogue table.
    }

    final response = await http
        .get(Uri.parse('$_quoteBackgroundsBaseUrl/catalogue_manifest.json'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception(
        'Could not reach the share backgrounds (HTTP ${response.statusCode}). '
        'Check your connection and try again.',
      );
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final entries = (decoded['backgrounds'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(QuoteBackground.fromManifestEntry)
        .toList(growable: false);
    _cache = entries;
    _loadedAt = DateTime.now();
    return entries;
  }
}
