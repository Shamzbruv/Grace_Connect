import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/quote_background.dart';
import 'package:grace_connect/models/share_card_style.dart';
import 'package:grace_connect/widgets/share/shareable_quote_card.dart';

QuoteBackground _sampleBackground({String safeTextArea = 'center'}) {
  return QuoteBackground(
    assetPath: 'assets/quote_backgrounds/01_midnight_grace.png',
    title: 'Midnight Grace',
    category: 'Dark / Prayer',
    recommendedTextColor: Colors.white,
    safeTextArea: safeTextArea,
  );
}

void main() {
  group('QuoteBackground', () {
    test('parses a named color', () {
      final background = QuoteBackground.fromManifestEntry({
        'file': '01_midnight_grace.png',
        'title': 'Midnight Grace',
        'category': 'Dark / Prayer',
        'recommended_text_color': 'white',
        'safe_text_area': 'center',
      });
      expect(background.assetPath,
          'assets/quote_backgrounds/01_midnight_grace.png');
      expect(background.recommendedTextColor, Colors.white);
    });

    test('parses a hex color', () {
      final background = QuoteBackground.fromManifestEntry({
        'file': '02_morning_mercy.png',
        'recommended_text_color': '#10141C',
        'safe_text_area': 'upper-center',
      });
      expect(background.recommendedTextColor, const Color(0xFF10141C));
    });

    test('falls back to white for a missing or unparseable color', () {
      final background = QuoteBackground.fromManifestEntry({
        'file': 'x.png',
      });
      expect(background.recommendedTextColor, Colors.white);
    });
  });

  // Reads the manifest straight off disk (not through Flutter's rootBundle,
  // which some environments fail to populate under `flutter test` even
  // though it works in a real build) -- this still catches a manifest that
  // doesn't parse, references a missing file, or has drifted from what's
  // actually on disk, which is the real risk here.
  test('the on-disk manifest parses and matches the bundled images', () {
    final manifestFile =
        File('assets/quote_backgrounds/catalogue_manifest.json');
    expect(manifestFile.existsSync(), isTrue,
        reason: 'catalogue_manifest.json must ship next to the images');

    final decoded =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final entries = (decoded['backgrounds'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    // The catalogue is meant to grow -- this only pins a floor, not an
    // exact count, so adding a 13th background doesn't break this test.
    expect(entries.length, greaterThanOrEqualTo(12));

    for (final entry in entries) {
      final background = QuoteBackground.fromManifestEntry(entry);
      expect(background.title, isNotEmpty);
      final imageFile = File(background.assetPath);
      expect(imageFile.existsSync(), isTrue,
          reason: '${background.assetPath} is listed in the manifest but '
              'missing from disk');
    }
  });

  test('ShareCardStyle.copyWith only changes the given fields', () {
    const original = ShareCardStyle(
      backgroundIndex: 2,
      blurSigma: 3,
      darkenOpacity: 0.2,
      font: ShareCardFont.lora,
      textColor: ShareCardTextColor.gold,
    );
    final updated = original.copyWith(blurSigma: 8);
    expect(updated.blurSigma, 8);
    expect(updated.backgroundIndex, original.backgroundIndex);
    expect(updated.darkenOpacity, original.darkenOpacity);
    expect(updated.font, original.font);
    expect(updated.textColor, original.textColor);
  });

  group('ShareableQuoteCard', () {
    testWidgets('renders the quote, attribution, and the branding watermark',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareableQuoteCard(
              background: _sampleBackground(),
              style: const ShareCardStyle(backgroundIndex: 0),
              quoteText: 'For God so loved the world.',
              attribution: 'John 3:16 (KJV)',
            ),
          ),
        ),
      );
      // Real asset decoding is unavailable in this test environment, but
      // the text layer, layout, and watermark build independently of
      // whether the background image itself finished decoding.
      await tester.pump();

      expect(find.text('For God so loved the world.'), findsOneWidget);
      expect(find.text('John 3:16 (KJV)'), findsOneWidget);
      // The watermark is mandatory on every card -- there is no path that
      // omits it, so it must render unconditionally (even if the asset
      // itself can't decode, errorBuilder keeps the text label showing).
      expect(find.text('Grace Connect'), findsOneWidget);
    });

    testWidgets('omits the attribution line when none is given',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareableQuoteCard(
              background: _sampleBackground(),
              style: const ShareCardStyle(backgroundIndex: 0),
              quoteText: 'Be still and know.',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Be still and know.'), findsOneWidget);
      // The watermark still always renders.
      expect(find.text('Grace Connect'), findsOneWidget);
    });
  });
}
