import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/quote_background.dart';
import '../../models/share_card_style.dart';
import '../../theme/app_colors.dart';

/// The square, exportable quote/scripture card: a catalogue background
/// (optionally blurred/darkened) and the quote text in the chosen font,
/// size, and color. No watermark -- it used to overlay the bottom of the
/// card and collided with the text on longer quotes, so it was removed
/// rather than reserving space for it.
class ShareableQuoteCard extends StatelessWidget {
  const ShareableQuoteCard({
    super.key,
    required this.background,
    required this.style,
    required this.quoteText,
    this.attribution,
    this.sourceNote,
  });

  final QuoteBackground background;
  final ShareCardStyle style;
  final String quoteText;
  final String? attribution;

  /// Shown under the reference. The Daily Word is the app's own reflection
  /// drawn from a passage, not the passage itself -- without saying so, a
  /// shared card reads as though scripture said these exact words.
  final String? sourceNote;

  /// A size that fits the card on its own, before the member touches the
  /// slider. The card is square and the text block is the only thing in it,
  /// so length is a good predictor: a 60-word Daily Word at 24pt overflows,
  /// while a short verse at 15pt looks lost. The slider still scales on top
  /// of this, so choosing a size by hand keeps working.
  double _autoFitBaseSize() {
    final characters = quoteText.trim().length;
    if (characters <= 70) return 26;
    if (characters <= 140) return 23;
    if (characters <= 220) return 20;
    if (characters <= 320) return 17.5;
    if (characters <= 430) return 15.5;
    if (characters <= 560) return 14;
    return 12.5;
  }

  Alignment _textAlignmentFor(String safeArea) {
    switch (safeArea) {
      case 'upper-center':
        return const Alignment(0, -0.35);
      case 'center-right':
        return const Alignment(0.15, 0);
      case 'left-center':
        return const Alignment(-0.15, 0);
      default:
        return Alignment.center;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = style.textColor.color;
    final baseSize = _autoFitBaseSize();
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A blur this strong needs headroom past the card's own edges,
            // or ImageFiltered's edge sampling shows a thin unblurred rim.
            Transform.scale(
              scale: 1.08,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: style.blurSigma,
                  sigmaY: style.blurSigma,
                  tileMode: TileMode.decal,
                ),
                child: CachedNetworkImage(
                  imageUrl: background.imageUrl,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  // A background that's still downloading, or failed to
                  // (offline, storage outage), must never crash the whole
                  // card or show a blank hole -- the quote is the part that
                  // actually has to reach whoever it's shared with.
                  // _share() precaches this same URL before capture, so in
                  // the normal path this placeholder never actually paints
                  // -- it's the fallback for whatever precache missed.
                  placeholder: (context, url) =>
                      Container(color: AppColors.primary),
                  errorWidget: (context, url, error) =>
                      Container(color: AppColors.primary),
                ),
              ),
            ),
            if (style.darkenOpacity > 0)
              Container(
                  color: Colors.black.withValues(alpha: style.darkenOpacity)),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
              child: Align(
                alignment: _textAlignmentFor(background.safeTextArea),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 300,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          quoteText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.getFont(
                            style.font.familyName,
                            textStyle: TextStyle(
                              color: textColor,
                              fontSize: baseSize * style.fontScale,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (attribution != null &&
                            attribution!.trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            attribution!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              style.font.familyName,
                              textStyle: TextStyle(
                                color: textColor.withValues(alpha: 0.9),
                                fontSize: (baseSize * 0.62).clamp(11, 18) *
                                    style.fontScale,
                                fontWeight: FontWeight.w600,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                        if (sourceNote != null &&
                            sourceNote!.trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            sourceNote!,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              style.font.familyName,
                              textStyle: TextStyle(
                                color: textColor.withValues(alpha: 0.75),
                                fontSize: (baseSize * 0.46).clamp(9, 13) *
                                    style.fontScale,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
