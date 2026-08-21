import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One curated background from assets/quote_backgrounds/, loaded from
/// catalogue_manifest.json rather than hardcoded -- new backgrounds can be
/// added by dropping a PNG and a manifest entry, no Dart changes needed.
class QuoteBackground {
  const QuoteBackground({
    required this.assetPath,
    required this.title,
    required this.category,
    required this.recommendedTextColor,
    required this.safeTextArea,
  });

  final String assetPath;
  final String title;
  final String category;
  final Color recommendedTextColor;
  final String safeTextArea;

  factory QuoteBackground.fromManifestEntry(Map<String, dynamic> entry) {
    return QuoteBackground(
      assetPath: 'assets/quote_backgrounds/${entry['file']}',
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
    final raw = await rootBundle
        .loadString('assets/quote_backgrounds/catalogue_manifest.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (decoded['backgrounds'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(QuoteBackground.fromManifestEntry)
        .toList(growable: false);
    _cache = entries;
    return entries;
  }
}
