import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/quote_background.dart';
import '../../models/share_card_style.dart';
import '../ui/app_feedback.dart';
import 'shareable_quote_card.dart';

/// Opens the background/style customizer, then shares the flattened card as
/// an image. This is the one entry point both Daily Word and Bible verse
/// sharing use, so a change to the customizer or the branding watermark
/// only has to happen in one place.
Future<void> showShareCardCustomizer(
  BuildContext context, {
  required String quoteText,
  String? attribution,
  required String shareFileName,
  required String shareText,
  String? shareSubject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ShareCardCustomizerSheet(
      quoteText: quoteText,
      attribution: attribution,
      shareFileName: shareFileName,
      shareText: shareText,
      shareSubject: shareSubject,
    ),
  );
}

class _ShareCardCustomizerSheet extends StatefulWidget {
  const _ShareCardCustomizerSheet({
    required this.quoteText,
    required this.attribution,
    required this.shareFileName,
    required this.shareText,
    required this.shareSubject,
  });

  final String quoteText;
  final String? attribution;
  final String shareFileName;
  final String shareText;
  final String? shareSubject;

  @override
  State<_ShareCardCustomizerSheet> createState() =>
      _ShareCardCustomizerSheetState();
}

class _ShareCardCustomizerSheetState
    extends State<_ShareCardCustomizerSheet> {
  final _previewKey = GlobalKey();
  late Future<List<QuoteBackground>> _backgroundsFuture;
  ShareCardStyle? _style;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _backgroundsFuture = QuoteBackgroundCatalogue.load();
  }

  void _selectBackground(int index, QuoteBackground background) {
    setState(() {
      _style = (_style ?? const ShareCardStyle(backgroundIndex: 0))
          .copyWith(backgroundIndex: index);
    });
  }

  Future<void> _share(QuoteBackground background) async {
    setState(() => _isSharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _previewKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('The card preview is not ready yet.');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) {
        throw Exception('Could not prepare the image.');
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pngBytes,
              mimeType: 'image/png',
              name: '${widget.shareFileName}.png',
            ),
          ],
          text: widget.shareText,
          subject: widget.shareSubject,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not share: $error',
        type: AppFeedbackType.error,
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<QuoteBackground>>(
      future: _backgroundsFuture,
      builder: (context, snapshot) {
        final backgrounds = snapshot.data;
        if (backgrounds == null) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (backgrounds.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(child: Text('No backgrounds are available yet.')),
          );
        }

        final style = _style ?? const ShareCardStyle(backgroundIndex: 0);
        final background = backgrounds[style.backgroundIndex];

        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => SafeArea(
            top: false,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: theme.dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Customize card',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: RepaintBoundary(
                      key: _previewKey,
                      child: ShareableQuoteCard(
                        background: background,
                        style: style,
                        quoteText: widget.quoteText,
                        attribution: widget.attribution,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Background', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: backgrounds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final option = backgrounds[index];
                      final selected = index == style.backgroundIndex;
                      return GestureDetector(
                        onTap: () => _selectBackground(index, option),
                        child: Container(
                          width: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.asset(
                              option.assetPath,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text('Blur background', style: theme.textTheme.labelLarge),
                Slider(
                  value: style.blurSigma,
                  min: 0,
                  max: 12,
                  divisions: 12,
                  label: style.blurSigma == 0
                      ? 'Off'
                      : style.blurSigma.toStringAsFixed(0),
                  onChanged: (value) => setState(
                    () => _style = style.copyWith(blurSigma: value),
                  ),
                ),
                Text('Darken background', style: theme.textTheme.labelLarge),
                Slider(
                  value: style.darkenOpacity,
                  min: 0,
                  max: 0.75,
                  divisions: 15,
                  label: style.darkenOpacity == 0
                      ? 'Off'
                      : '${(style.darkenOpacity * 100).round()}%',
                  onChanged: (value) => setState(
                    () => _style = style.copyWith(darkenOpacity: value),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Font', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final font in ShareCardFont.values)
                      ChoiceChip(
                        label: Text(
                          font.label,
                          style: GoogleFonts.getFont(font.familyName),
                        ),
                        selected: style.font == font,
                        onSelected: (_) => setState(
                          () => _style = style.copyWith(font: font),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Text color', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final option in ShareCardTextColor.values)
                      GestureDetector(
                        onTap: () => setState(
                          () => _style = style.copyWith(textColor: option),
                        ),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: option.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: style.textColor == option
                                  ? theme.colorScheme.primary
                                  : theme.dividerColor,
                              width: style.textColor == option ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSharing ? null : () => _share(background),
                  icon: _isSharing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_outlined),
                  label: Text(_isSharing ? 'Preparing…' : 'Share'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
