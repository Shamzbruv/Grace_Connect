import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import '../models/post.dart';
import '../models/reel.dart';
import 'community_service.dart';
import 'reel_service.dart';
import 'media_export_stub.dart' if (dart.library.io) 'media_export_io.dart'
    as exporter;

class ContentShareService {
  static bool _exporting = false;
  static const maxBytes = 100 * 1024 * 1024;

  static Future<void> shareExternal(BuildContext context,
      {Reel? reel, Post? post}) async {
    if (_exporting) return;
    _exporting = true;
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    final client = http.Client();
    try {
      String? url;
      String text;
      bool video;
      if (reel != null) {
        final service = ReelService();
        final current = await service.fetchDetail(reel.id);
        if (current == null) {
          throw const FormatException('This reel is no longer available.');
        }
        if (current.visibility != ReelVisibility.public) {
          throw const FormatException(
              'Only public reels can be shared outside Grace Connect.');
        }
        url = (await service.refreshMedia(current.id))?.videoUrl;
        if (url == null) {
          throw const FormatException('This video could not be downloaded.');
        }
        text = current.caption;
        video = true;
      } else {
        final current = await CommunityService().fetchPostById(post!.id);
        if (current == null) {
          throw const FormatException('This post is no longer available.');
        }
        if (!current.visibleToAllChurches &&
            current.scope != 'global' &&
            current.scope != 'discover' &&
            current.scope != 'public') {
          throw const FormatException(
              'Church-only posts can be shared within Grace Connect.');
        }
        url = current.mediaUrl;
        text = current.content;
        video = current.mediaType?.startsWith('video') == true;
      }
      XFile? file;
      if (url?.isNotEmpty == true) {
        messenger.showSnackBar(SnackBar(
            duration: const Duration(minutes: 5),
            content: Text(video
                ? 'Preparing video with Grace Connect watermark…'
                : 'Preparing image…')));
        final uri = Uri.parse(url!);
        if (uri.scheme != 'https') {
          throw const FormatException('This media address is unavailable.');
        }
        final response = await client
            .send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw const FormatException('Download failed. Please try again.');
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          throw const FormatException('This file is too large to share.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('This file is too large to share.');
          }
          bytes.add(chunk);
        }
        final mime = response.headers['content-type']?.split(';').first ??
            (video ? 'video/mp4' : 'image/jpeg');
        file = await exporter.prepareExport(bytes.takeBytes(),
            video: video, mimeType: mime);
      }
      messenger.hideCurrentSnackBar();
      await SharePlus.instance.share(ShareParams(
        text: text.isEmpty ? null : text,
        subject: 'Shared from Grace Connect',
        files: file == null ? null : [file],
        sharePositionOrigin: origin,
      ));
    } catch (error) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(error is FormatException
              ? error.message
              : error is UnsupportedError
                  ? error.message ?? 'Export unavailable.'
                  : 'Could not prepare this share. Please try again.')));
    } finally {
      client.close();
      _exporting = false;
    }
  }
}
