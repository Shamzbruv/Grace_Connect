import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  static Future<List<QuoteBackground>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
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
    return entries;
  }
}
