import 'package:flutter/material.dart';

/// Curated font choices for shared quote/scripture cards. Family names are
/// passed straight to GoogleFonts.getFont -- adding a font later is a
/// one-line addition here, not a new import per font.
enum ShareCardFont {
  poppins('Poppins', 'Poppins'),
  outfit('Outfit', 'Outfit'),
  lora('Lora', 'Lora (serif)'),
  merriweather('Merriweather', 'Merriweather (serif)'),
  playfairDisplay('Playfair Display', 'Playfair (elegant)'),
  caveat('Caveat', 'Caveat (handwritten)');

  const ShareCardFont(this.familyName, this.label);

  final String familyName;
  final String label;
}

/// A small, fixed set of text colors that stay legible over any catalogue
/// background (paired with the darken scrim) -- an open color picker
/// invites choosing text that vanishes into a similarly-toned background.
enum ShareCardTextColor {
  white('White', Colors.white),
  black('Black', Color(0xFF1A1A1A)),
  gold('Gold', Color(0xFFD2982C)),
  navy('Navy', Color(0xFF10141C));

  const ShareCardTextColor(this.label, this.color);

  final String label;
  final Color color;
}

/// The user's customization choices for one shared card. Immutable --
/// callers build a new instance via copyWith rather than mutate in place.
class ShareCardStyle {
  const ShareCardStyle({
    required this.backgroundIndex,
    this.blurSigma = 0,
    this.darkenOpacity = 0.25,
    this.font = ShareCardFont.poppins,
    this.textColor = ShareCardTextColor.white,
  });

  final int backgroundIndex;
  final double blurSigma;
  final double darkenOpacity;
  final ShareCardFont font;
  final ShareCardTextColor textColor;

  ShareCardStyle copyWith({
    int? backgroundIndex,
    double? blurSigma,
    double? darkenOpacity,
    ShareCardFont? font,
    ShareCardTextColor? textColor,
  }) {
    return ShareCardStyle(
      backgroundIndex: backgroundIndex ?? this.backgroundIndex,
      blurSigma: blurSigma ?? this.blurSigma,
      darkenOpacity: darkenOpacity ?? this.darkenOpacity,
      font: font ?? this.font,
      textColor: textColor ?? this.textColor,
    );
  }
}
