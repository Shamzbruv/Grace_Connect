import 'package:youtube_player_flutter/youtube_player_flutter.dart';

class YoutubeUrlUtils {
  static final RegExp _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static String? extractVideoId(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;

    if (_videoIdPattern.hasMatch(raw)) return raw;

    final pluginId = YoutubePlayer.convertUrlToId(raw);
    if (pluginId != null && _videoIdPattern.hasMatch(pluginId)) {
      return pluginId;
    }

    final normalized = raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : raw.startsWith('www.') || raw.startsWith('m.')
            ? 'https://$raw'
            : raw.startsWith('/watch') || raw.startsWith('/live')
                ? 'https://youtube.com$raw'
                : raw.startsWith('youtube.com')
                    ? 'https://$raw'
                    : raw;

    final uri = Uri.tryParse(normalized);
    if (uri == null) return _extractFromLooseText(raw);

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;

    if (host == 'youtu.be' && segments.isNotEmpty) {
      return _cleanVideoId(segments.first);
    }

    final watchId = uri.queryParameters['v'];
    if (watchId != null) return _cleanVideoId(watchId);

    for (final marker in ['live', 'embed', 'shorts', 'v']) {
      final markerIndex = segments.indexWhere(
        (segment) => segment.toLowerCase() == marker,
      );
      if (markerIndex >= 0 && markerIndex < segments.length - 1) {
        return _cleanVideoId(segments[markerIndex + 1]);
      }
    }

    if (segments.isNotEmpty) return _cleanVideoId(segments.last);
    return _extractFromLooseText(raw);
  }

  static String? normalizeWatchUrl(String value) {
    final videoId = extractVideoId(value);
    if (videoId == null) return null;
    return 'https://www.youtube.com/watch?v=$videoId';
  }

  static String? _cleanVideoId(String value) {
    final cleaned = value.trim().split(RegExp(r'[?&#/]')).first;
    return _videoIdPattern.hasMatch(cleaned) ? cleaned : null;
  }

  static String? _extractFromLooseText(String value) {
    final match = RegExp(r'([A-Za-z0-9_-]{11})').firstMatch(value);
    return match?.group(1);
  }
}
