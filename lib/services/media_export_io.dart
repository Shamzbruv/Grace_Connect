import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _channel = MethodChannel('love.graceconnect/media_export');

Future<XFile> prepareExport(Uint8List bytes,
    {required bool video, required String mimeType}) async {
  final root =
      Directory('${(await getTemporaryDirectory()).path}/grace_exports');
  await root.create(recursive: true);
  // Keep completed exports briefly so the receiving app can finish copying.
  await for (final entry in root.list()) {
    if (entry is File &&
        DateTime.now().difference((await entry.stat()).modified) >
            const Duration(days: 1)) {
      try {
        await entry.delete();
      } catch (_) {/* OS may still hold an export. */}
    }
  }
  final extension = video
      ? 'mp4'
      : mimeType == 'image/png'
          ? 'png'
          : mimeType == 'image/webp'
              ? 'webp'
              : 'jpg';
  final input = File(
      '${root.path}/grace-connect-${DateTime.now().microsecondsSinceEpoch}.$extension');
  await input.writeAsBytes(bytes, flush: true);
  if (!video) return XFile(input.path, mimeType: mimeType);
  try {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
          'Video export is available on Android and iPhone.');
    }
    final path = await _channel
        .invokeMethod<String>('watermark', {'input': input.path}).timeout(
            const Duration(minutes: 5), onTimeout: () async {
      await _channel.invokeMethod<void>('cancel');
      throw const FormatException(
          'Video preparation timed out. Please try again.');
    });
    if (path == null || !await File(path).exists()) {
      throw const FormatException('Video preparation failed.');
    }
    return XFile(path, mimeType: 'video/mp4');
  } finally {
    await input.delete();
  }
}
