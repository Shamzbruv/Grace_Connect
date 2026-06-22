import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum MediaDisplayFormat {
  fill('Fill', 'Crop edges to fill the frame', 'cover', null),
  full('Full Image', 'Show the whole photo', 'contain', null),
  square('Square', 'Best for balanced photos', 'cover', 1),
  portrait('Portrait', 'Best for flyers and stories', 'cover', 4 / 5),
  landscape('Landscape', 'Best for banners', 'cover', 16 / 9);

  const MediaDisplayFormat(
    this.label,
    this.description,
    this.mediaFit,
    this.aspectRatio,
  );

  final String label;
  final String description;
  final String mediaFit;
  final double? aspectRatio;
}

BoxFit boxFitForMedia(String mediaFit) {
  return mediaFit == 'contain' ? BoxFit.contain : BoxFit.cover;
}

double safeMediaAspectRatio(double? ratio, {double fallback = 4 / 3}) {
  if (ratio == null || ratio.isNaN || ratio.isInfinite) return fallback;
  return ratio.clamp(0.56, 1.9).toDouble();
}

Future<double?> imageAspectRatioFromBytes(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    if (image.height == 0) return null;
    return image.width / image.height;
  } catch (_) {
    return null;
  }
}
