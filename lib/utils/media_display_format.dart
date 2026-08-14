import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum MediaDisplayFormat {
  fill('Fill', 'Crop edges to fill the frame', 'cover', null),
  full('Full Media', 'Show the whole photo or video', 'contain', null),
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

enum MediaOrientation { portrait, square, landscape, unknown }

class MediaFormatRecommendation {
  const MediaFormatRecommendation({
    required this.orientation,
    required this.format,
    required this.sourceAspectRatio,
  });

  final MediaOrientation orientation;
  final MediaDisplayFormat format;
  final double? sourceAspectRatio;

  String get orientationLabel => switch (orientation) {
        MediaOrientation.portrait => 'Portrait',
        MediaOrientation.square => 'Square',
        MediaOrientation.landscape => 'Landscape',
        MediaOrientation.unknown => 'Media',
      };

  String get summary {
    final ratio = sourceAspectRatio;
    final dimensions = ratio == null ? '' : ' • ${ratio.toStringAsFixed(2)}:1';
    return '$orientationLabel detected$dimensions. Full Media is recommended so no edge is cropped.';
  }
}

/// Detects the source orientation and recommends the lossless display option.
///
/// Grace Connect defaults to [MediaDisplayFormat.full] after inspecting a
/// photo or video. Members can still deliberately choose a crop format, but
/// the automatic choice always preserves the complete flyer/frame.
MediaFormatRecommendation recommendMediaDisplayFormat(double? aspectRatio) {
  final safeRatio = aspectRatio == null ||
          aspectRatio.isNaN ||
          aspectRatio.isInfinite ||
          aspectRatio <= 0
      ? null
      : aspectRatio;
  final orientation = safeRatio == null
      ? MediaOrientation.unknown
      : safeRatio < 0.92
          ? MediaOrientation.portrait
          : safeRatio > 1.08
              ? MediaOrientation.landscape
              : MediaOrientation.square;

  return MediaFormatRecommendation(
    orientation: orientation,
    format: MediaDisplayFormat.full,
    sourceAspectRatio: safeRatio,
  );
}

BoxFit boxFitForMedia(String mediaFit) {
  return mediaFit == 'contain' ? BoxFit.contain : BoxFit.cover;
}

double safeMediaAspectRatio(double? ratio, {double fallback = 4 / 3}) {
  if (ratio == null || ratio.isNaN || ratio.isInfinite) return fallback;
  return ratio.clamp(0.56, 1.9).toDouble();
}

Future<double?> imageAspectRatioFromBytes(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    image = frame.image;
    if (image.height == 0) return null;
    return image.width / image.height;
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
