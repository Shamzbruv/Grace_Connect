import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/quote_background.dart';

/// One catalogue row as the developer screen sees it, including the inactive
/// ones that members never receive.
class QuoteBackgroundRecord {
  const QuoteBackgroundRecord({
    required this.id,
    required this.fileName,
    required this.title,
    required this.category,
    required this.recommendedTextColor,
    required this.safeTextArea,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String fileName;
  final String title;
  final String category;
  final String recommendedTextColor;
  final String safeTextArea;
  final int sortOrder;
  final bool isActive;

  String get imageUrl => QuoteBackgroundCatalogue.publicUrlFor(fileName);

  factory QuoteBackgroundRecord.fromRow(Map<String, dynamic> row) {
    return QuoteBackgroundRecord(
      id: row['id'].toString(),
      fileName: row['file_name']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      category: row['category']?.toString() ?? '',
      recommendedTextColor:
          row['recommended_text_color']?.toString() ?? 'white',
      safeTextArea: row['safe_text_area']?.toString() ?? 'center',
      sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] == true,
    );
  }
}

/// Developer-only management of the share-card background catalogue.
///
/// Every write here is gated twice: this screen is only reachable from the
/// developer console, and the database policies independently require a
/// developer account. The second check is the one that matters -- the first
/// is only navigation.
class QuoteBackgroundAdminService {
  QuoteBackgroundAdminService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String bucket = 'quote-backgrounds';
  static const String folder = 'quote_backgrounds';

  Future<List<QuoteBackgroundRecord>> list() async {
    final rows = await _client.rpc('developer_list_quote_backgrounds');
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(QuoteBackgroundRecord.fromRow)
        .toList();
  }

  /// Uploads the image, then records it.
  ///
  /// In that order deliberately: a row pointing at an object that failed to
  /// upload would render as a broken tile in every member's share sheet,
  /// whereas an uploaded object with no row is invisible and harmless.
  Future<void> add({
    required Uint8List bytes,
    required String fileName,
    required String title,
    required String category,
    required String recommendedTextColor,
    required String safeTextArea,
  }) async {
    final safeName = sanitiseFileName(fileName);
    await _client.storage.from(bucket).uploadBinary(
          '$folder/$safeName',
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(safeName),
            upsert: false,
          ),
        );

    try {
      final highest = await _client
          .from('quote_backgrounds')
          .select('sort_order')
          .order('sort_order', ascending: false)
          .limit(1);
      final nextOrder = highest.isEmpty
          ? 1
          : ((highest.first['sort_order'] as num?)?.toInt() ?? 0) + 1;

      await _client.from('quote_backgrounds').insert({
        'file_name': safeName,
        'title': title.trim(),
        'category': category.trim(),
        'recommended_text_color': recommendedTextColor,
        'safe_text_area': safeTextArea,
        'sort_order': nextOrder,
        'is_active': true,
        'created_by': _client.auth.currentUser?.id,
      });
    } catch (_) {
      // Roll back only this new upload; never overwrite an existing object.
      try {
        await _client.storage.from(bucket).remove(['$folder/$safeName']);
      } catch (_) {
        // The original database error is the actionable failure.
      }
      rethrow;
    }
    QuoteBackgroundCatalogue.invalidate();
  }

  Future<void> update(
    String id, {
    String? title,
    String? category,
    String? recommendedTextColor,
    String? safeTextArea,
    bool? isActive,
    int? sortOrder,
  }) async {
    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String()
    };
    if (title != null) patch['title'] = title.trim();
    if (category != null) patch['category'] = category.trim();
    if (recommendedTextColor != null) {
      patch['recommended_text_color'] = recommendedTextColor;
    }
    if (safeTextArea != null) patch['safe_text_area'] = safeTextArea;
    if (isActive != null) patch['is_active'] = isActive;
    if (sortOrder != null) patch['sort_order'] = sortOrder;

    await _client.from('quote_backgrounds').update(patch).eq('id', id);
    QuoteBackgroundCatalogue.invalidate();
  }

  /// Removes the row, then the object.
  ///
  /// The row goes first for the same reason it is written last: once it is
  /// gone nobody can be handed a link to the image, so a failure deleting the
  /// object leaves an orphan file rather than a broken card.
  Future<void> remove(QuoteBackgroundRecord record) async {
    await _client.from('quote_backgrounds').delete().eq('id', record.id);
    try {
      await _client.storage.from(bucket).remove(['$folder/${record.fileName}']);
    } catch (_) {
      // An orphaned object costs a few hundred kilobytes and nothing else.
    }
    QuoteBackgroundCatalogue.invalidate();
  }

  /// Strips anything the database's file-name constraint would reject, and
  /// anything that could point the share card outside its folder.
  static String sanitiseFileName(String raw) {
    final base = raw.split('/').last.split('\\').last.trim().toLowerCase();
    final cleaned = base.replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
    final withExtension = RegExp(r'\.(png|jpg|jpeg|webp)$').hasMatch(cleaned)
        ? cleaned
        : '$cleaned.png';
    // Prefixed so two uploads of "background.png" cannot collide.
    return '${const Uuid().v4()}_$withExtension';
  }

  static String _contentTypeFor(String fileName) {
    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (fileName.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }
}
