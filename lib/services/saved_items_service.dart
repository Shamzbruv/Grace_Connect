import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedItem {
  const SavedItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    this.title = '',
    this.subtitle = '',
    this.mediaUrl = '',
    this.mediaType = '',
    this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String title;
  final String subtitle;
  final String mediaUrl;
  final String mediaType;
  final DateTime? createdAt;

  factory SavedItem.fromMap(Map<String, dynamic> data) {
    final metadata = data['metadata'];
    final metadataMap =
        metadata is Map ? Map<String, dynamic>.from(metadata) : const {};
    return SavedItem(
      id: data['id']?.toString() ?? '',
      entityType: data['entity_type']?.toString() ?? '',
      entityId: data['entity_id']?.toString() ?? '',
      title:
          metadataMap['title']?.toString() ?? data['title']?.toString() ?? '',
      subtitle: metadataMap['subtitle']?.toString() ??
          data['subtitle']?.toString() ??
          '',
      mediaUrl: metadataMap['media_url']?.toString() ??
          data['media_url']?.toString() ??
          '',
      mediaType: metadataMap['media_type']?.toString() ??
          data['media_type']?.toString() ??
          '',
      createdAt: _dateValue(data['created_at']),
    );
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

class SavedItemsService {
  SavedItemsService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String? get _userId => _supabase.auth.currentUser?.id;

  Future<List<SavedItem>> fetchSavedItems() async {
    final userId = _userId;
    if (userId == null) return const [];

    try {
      final rows = await _supabase
          .from('social_saved_items')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
      return rows
          .map((row) => SavedItem.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error) {
      debugPrint('Saved items unavailable: $error');
      return _localSavedItems(userId);
    }
  }

  Future<bool> isSaved({
    required String entityType,
    required String entityId,
  }) async {
    final userId = _userId;
    if (userId == null || entityId.trim().isEmpty) return false;

    try {
      final row = await _supabase
          .from('social_saved_items')
          .select('id')
          .eq('user_id', userId)
          .eq('entity_type', entityType)
          .eq('entity_id', entityId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return _isSavedLocally(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
      );
    }
  }

  Future<void> save({
    required String entityType,
    required String entityId,
    String title = '',
    String subtitle = '',
    String mediaUrl = '',
    String mediaType = '',
  }) async {
    final userId = _userId;
    if (userId == null || entityId.trim().isEmpty) return;

    try {
      await _supabase.from('social_saved_items').upsert(
        {
          'user_id': userId,
          'entity_type': entityType,
          'entity_id': entityId,
          'metadata': {
            'title': title,
            'subtitle': subtitle,
            'media_url': mediaUrl,
            'media_type': mediaType,
          },
        },
        onConflict: 'user_id,entity_type,entity_id',
      );
    } catch (error) {
      debugPrint('Saved items table unavailable, using local save: $error');
      await _saveLocally(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        title: title,
        subtitle: subtitle,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
    }
  }

  Future<void> unsave({
    required String entityType,
    required String entityId,
  }) async {
    final userId = _userId;
    if (userId == null || entityId.trim().isEmpty) return;

    try {
      await _supabase
          .from('social_saved_items')
          .delete()
          .eq('user_id', userId)
          .eq('entity_type', entityType)
          .eq('entity_id', entityId);
    } catch (error) {
      debugPrint('Saved items table unavailable, using local unsave: $error');
      await _unsaveLocally(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
      );
    }
  }

  String _localKey(String userId) => 'local_social_saved_items_$userId';

  Future<List<SavedItem>> _localSavedItems(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(_localKey(userId)) ?? const [];
    return rawItems
        .map((raw) {
          try {
            return SavedItem.fromMap(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedItem>()
        .toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
  }

  Future<bool> _isSavedLocally({
    required String userId,
    required String entityType,
    required String entityId,
  }) async {
    final items = await _localSavedItems(userId);
    return items.any(
      (item) => item.entityType == entityType && item.entityId == entityId,
    );
  }

  Future<void> _saveLocally({
    required String userId,
    required String entityType,
    required String entityId,
    required String title,
    required String subtitle,
    required String mediaUrl,
    required String mediaType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _localKey(userId);
    final rawItems = prefs.getStringList(key) ?? <String>[];
    final next = rawItems.where((raw) {
      try {
        final item = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        return item['entity_type'] != entityType ||
            item['entity_id'] != entityId;
      } catch (_) {
        return false;
      }
    }).toList()
      ..add(jsonEncode({
        'id': 'local_${entityType}_$entityId',
        'entity_type': entityType,
        'entity_id': entityId,
        'metadata': {
          'title': title,
          'subtitle': subtitle,
          'media_url': mediaUrl,
          'media_type': mediaType,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }));
    await prefs.setStringList(key, next);
  }

  Future<void> _unsaveLocally({
    required String userId,
    required String entityType,
    required String entityId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _localKey(userId);
    final rawItems = prefs.getStringList(key) ?? <String>[];
    final next = rawItems.where((raw) {
      try {
        final item = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        return item['entity_type'] != entityType ||
            item['entity_id'] != entityId;
      } catch (_) {
        return false;
      }
    }).toList();
    await prefs.setStringList(key, next);
  }
}
