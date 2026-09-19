import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/reel.dart';

/// Limits mirrored from the server. These are a courtesy so the member finds
/// out before a long upload, not a control: create-reel-upload and
/// finalize-reel-upload enforce the real ones, because this runs on a device
/// and anyone can call the endpoint directly.
class ReelUploadLimits {
  static const int maxVideoBytes = 25 * 1024 * 1024;
  static const int maxPosterBytes = 500 * 1024;
  static const Duration maxDuration = Duration(seconds: 60);
  static const Duration minDuration = Duration(milliseconds: 500);
}

enum ReelUploadStage { preparing, requesting, uploadingVideo, uploadingPoster, publishing, done, failed }

class ReelUploadProgress {
  const ReelUploadProgress({
    required this.stage,
    this.fraction = 0,
    this.message,
  });

  final ReelUploadStage stage;
  final double fraction;
  final String? message;
}

class ReelUploadException implements Exception {
  ReelUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Prepares and uploads a reel.
///
/// The device never holds an R2 credential. It asks the server for a
/// short-lived presigned PUT, uploads the bytes straight to R2, then asks the
/// server to publish. If it stops anywhere in between, the upload session
/// expires and the scheduled sweep removes whatever landed -- so an abandoned
/// attempt cannot leave a permanent orphan.
class ReelUploadService {
  ReelUploadService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void _checkCancelled() {
    if (_cancelled) throw ReelUploadException('Upload cancelled.');
  }

  /// Inspects the chosen file and rejects anything outside the reel format
  /// before a byte is uploaded.
  ///
  /// V1 validates and rejects rather than silently transcoding: the
  /// maintained Flutter transcoding options were not worth taking on for
  /// launch, and a wrong transcode is worse than a clear message. Capture is
  /// constrained to 60s at the picker, so the common path is already within
  /// limits. Server-side inspection can tighten this later.
  Future<ReelSource> prepare(File video) async {
    final length = await video.length();
    if (length <= 0) {
      throw ReelUploadException('That video file looks empty.');
    }
    if (length > ReelUploadLimits.maxVideoBytes) {
      final mb = (length / (1024 * 1024)).toStringAsFixed(1);
      throw ReelUploadException(
        'That video is ${mb}MB. Reels need to be under 25MB -- try a shorter '
        'clip or record at a lower quality.',
      );
    }

    final controller = VideoPlayerController.file(video);
    Duration duration;
    double? aspectRatio;
    int? width;
    int? height;
    try {
      await controller.initialize().timeout(const Duration(seconds: 20));
      duration = controller.value.duration;
      aspectRatio = controller.value.aspectRatio;
      width = controller.value.size.width.round();
      height = controller.value.size.height.round();
    } catch (_) {
      throw ReelUploadException('That file could not be read as a video.');
    } finally {
      unawaited(controller.dispose());
    }

    if (duration > ReelUploadLimits.maxDuration) {
      final seconds = duration.inSeconds;
      throw ReelUploadException(
        'That clip is ${seconds}s. Reels can be up to 60 seconds -- trim it '
        'and try again.',
      );
    }
    if (duration < ReelUploadLimits.minDuration) {
      throw ReelUploadException('That clip is too short to post.');
    }

    final poster = await _generatePoster(video);
    return ReelSource(
      video: video,
      poster: poster,
      durationMs: duration.inMilliseconds,
      videoBytes: length,
      posterBytes: await poster.length(),
      aspectRatio: aspectRatio,
      width: width,
      height: height,
    );
  }

  Future<File> _generatePoster(File video) async {
    final directory = await getTemporaryDirectory();
    final path = await VideoThumbnail.thumbnailFile(
      video: video.path,
      thumbnailPath: directory.path,
      imageFormat: ImageFormat.WEBP,
      maxWidth: 720,
      quality: 80,
    );
    if (path == null) {
      throw ReelUploadException('A cover image could not be made for that video.');
    }
    final poster = File(path);
    if (await poster.length() > ReelUploadLimits.maxPosterBytes) {
      // Retry smaller rather than failing the whole upload on the cover.
      final smaller = await VideoThumbnail.thumbnailFile(
        video: video.path,
        thumbnailPath: directory.path,
        imageFormat: ImageFormat.WEBP,
        maxWidth: 480,
        quality: 60,
      );
      if (smaller != null) return File(smaller);
    }
    return poster;
  }

  /// Runs the whole publish. Returns the reel id.
  Future<String> publish({
    required ReelSource source,
    required String caption,
    required String category,
    required ReelVisibility visibility,
    void Function(ReelUploadProgress)? onProgress,
  }) async {
    _cancelled = false;
    void report(ReelUploadStage stage, double fraction, [String? message]) =>
        onProgress?.call(ReelUploadProgress(
            stage: stage, fraction: fraction, message: message));

    report(ReelUploadStage.requesting, 0.02, 'Preparing upload');
    _checkCancelled();

    final created = await _client.functions.invoke('create-reel-upload', body: {
      'video_content_type': 'video/mp4',
      'video_size': source.videoBytes,
      'poster_content_type': 'image/webp',
      'poster_size': source.posterBytes,
      'duration_ms': source.durationMs,
    });
    final createdData = created.data;
    if (createdData is! Map || createdData['reel_id'] == null) {
      final message = createdData is Map
          ? (createdData['error']?.toString() ?? 'Could not start the upload.')
          : 'Could not start the upload.';
      throw ReelUploadException(message);
    }
    final envelope = Map<String, dynamic>.from(createdData);
    final reelId = envelope['reel_id'].toString();

    _checkCancelled();
    report(ReelUploadStage.uploadingVideo, 0.08, 'Uploading video');
    await _putFile(
      url: envelope['video_upload_url'].toString(),
      file: source.video,
      contentType: envelope['video_content_type']?.toString() ?? 'video/mp4',
      onProgress: (sent, total) => report(
        ReelUploadStage.uploadingVideo,
        0.08 + 0.74 * (total == 0 ? 0 : sent / total),
        'Uploading video',
      ),
    );

    _checkCancelled();
    report(ReelUploadStage.uploadingPoster, 0.86, 'Uploading cover');
    await _putFile(
      url: envelope['poster_upload_url'].toString(),
      file: source.poster,
      contentType: envelope['poster_content_type']?.toString() ?? 'image/webp',
    );

    _checkCancelled();
    report(ReelUploadStage.publishing, 0.94, 'Publishing');
    final published = await _client.functions.invoke('finalize-reel-upload', body: {
      'reel_id': reelId,
      'caption': caption,
      'category': category,
      'visibility': visibility.wireName,
    });
    final publishedData = published.data;
    if (publishedData is! Map || publishedData['status'] != 'ready') {
      final message = publishedData is Map
          ? (publishedData['error']?.toString() ?? 'Could not publish the reel.')
          : 'Could not publish the reel.';
      throw ReelUploadException(message);
    }

    report(ReelUploadStage.done, 1, 'Posted');
    return reelId;
  }

  /// Streams the file so a 25MB video is not held in memory twice, and so
  /// progress can be reported while it uploads.
  Future<void> _putFile({
    required String url,
    required File file,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final total = await file.length();
    var sent = 0;
    final request = http.StreamedRequest('PUT', Uri.parse(url));
    // The signature covers Content-Type, so it must match exactly what the
    // server signed or R2 rejects the upload.
    request.headers['Content-Type'] = contentType;
    request.contentLength = total;

    unawaited(() async {
      try {
        await for (final chunk in file.openRead()) {
          if (_cancelled) break;
          request.sink.add(chunk);
          sent += chunk.length;
          onProgress?.call(sent, total);
        }
      } finally {
        await request.sink.close();
      }
    }());

    final response = await http.Client().send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('R2 upload failed ${response.statusCode}: $body');
      throw ReelUploadException(
        'The upload did not complete. Check your connection and try again.',
      );
    }
  }
}

class ReelSource {
  const ReelSource({
    required this.video,
    required this.poster,
    required this.durationMs,
    required this.videoBytes,
    required this.posterBytes,
    this.aspectRatio,
    this.width,
    this.height,
  });

  final File video;
  final File poster;
  final int durationMs;
  final int videoBytes;
  final int posterBytes;
  final double? aspectRatio;
  final int? width;
  final int? height;

  String get readableSize => videoBytes < 1024 * 1024
      ? '${(videoBytes / 1024).round()} KB'
      : '${(videoBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String get readableDuration => '${(durationMs / 1000).round()}s';
}
