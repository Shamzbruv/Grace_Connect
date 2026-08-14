import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'media_display_format.dart';

class CommunityVideoInspection {
  const CommunityVideoInspection({
    required this.thumbnailBytes,
    required this.aspectRatio,
    required this.byteLength,
  });

  final Uint8List? thumbnailBytes;
  final double? aspectRatio;
  final int byteLength;

  MediaFormatRecommendation get recommendation =>
      recommendMediaDisplayFormat(aspectRatio);
}

/// Generates a small poster frame once, immediately after selection. The
/// poster is reused by the composer and uploaded with the video so feed cards
/// can paint meaningful content before the network decoder is ready.
Future<CommunityVideoInspection> inspectCommunityVideo(
  XFile video, {
  int? maxByteLength,
}) async {
  final byteLength = await video.length();
  if (maxByteLength != null && byteLength > maxByteLength) {
    // Reject oversized raw videos before asking the platform decoder to seek
    // and render a thumbnail. That keeps selection feedback immediate and
    // matches the Storage bucket limit before any expensive work begins.
    return CommunityVideoInspection(
      thumbnailBytes: null,
      aspectRatio: null,
      byteLength: byteLength,
    );
  }
  Uint8List? thumbnailBytes;
  try {
    thumbnailBytes = await VideoThumbnail.thumbnailData(
      video: video.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 960,
      timeMs: 350,
      quality: 82,
    );
  } catch (_) {
    // Unsupported platforms/codecs may not expose a frame. Upload can still
    // continue, and the player will use its lightweight generic poster.
  }

  return CommunityVideoInspection(
    thumbnailBytes: thumbnailBytes,
    aspectRatio: thumbnailBytes == null
        ? null
        : await imageAspectRatioFromBytes(thumbnailBytes),
    byteLength: byteLength,
  );
}
