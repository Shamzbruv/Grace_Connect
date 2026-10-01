import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';

Future<XFile> prepareExport(Uint8List bytes,
    {required bool video, required String mimeType}) async {
  if (video) {
    throw UnsupportedError(
        'Use the Android or iPhone app to share a watermarked video.');
  }
  return XFile.fromData(bytes,
      mimeType: mimeType,
      name:
          'grace-connect.${mimeType == 'image/png' ? 'png' : mimeType == 'image/webp' ? 'webp' : 'jpg'}');
}
