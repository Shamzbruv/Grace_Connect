import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grace_connect/theme/app_colors.dart';
import 'package:grace_connect/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final previousRuntimeFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final bytes =
        await File('test/fixtures/fonts/Roboto-Regular.ttf').readAsBytes();
    final fontData = ByteData.sublistView(bytes);
    final fontAssets = {
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold'
      ])
        'test/fonts/Outfit-$weight.ttf': [
          {'asset': 'test/fonts/Outfit-$weight.ttf'}
        ],
    };
    // These tests assert colors, not glyph shapes. Supply a valid local font
    // through the asset channel so no asynchronous network/cache miss can leak
    // into another test after the first theme has been constructed.
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (key == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(fontAssets);
      }
      return fontAssets.containsKey(key) ? fontData : null;
    });
    AppTheme.lightTheme;
    AppTheme.darkTheme;
    await GoogleFonts.pendingFonts();
  });

  tearDownAll(() {
    messenger.setMockMessageHandler('flutter/assets', null);
    GoogleFonts.config.allowRuntimeFetching = previousRuntimeFetching;
  });
  test('primary, secondary and surface text stay readable in both themes', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final c = theme.colorScheme;
      expect(contrast(c.primary, c.onPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(c.secondary, c.onSecondary), greaterThanOrEqualTo(4.5));
      expect(contrast(c.surface, c.onSurface), greaterThanOrEqualTo(4.5));
      expect(contrast(c.secondary, c.surface), greaterThanOrEqualTo(4.5));
      for (final accent in [
        const Color(0xFF78C6A3),
        const Color(0xFF7DB9F1),
        const Color(0xFFF4B860)
      ]) {
        expect(contrast(AppColors.readableAccent(accent, c.surface), c.surface),
            greaterThanOrEqualTo(4.5));
      }
    }
  });
  testWidgets(
      'a navy Bible app bar keeps a white title and icons in light mode',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          appBar: AppBar(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              title: const Text('John 3'),
              leading: const Icon(Icons.arrow_back)),
        )));
    final title = tester.element(find.text('John 3'));
    expect(DefaultTextStyle.of(title).style.color, Colors.white);
    expect(IconTheme.of(tester.element(find.byIcon(Icons.arrow_back))).color,
        Colors.white);
  });
}
