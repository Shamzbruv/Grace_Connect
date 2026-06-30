import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/daily_motivation.dart';
import 'supabase_resilience.dart';

class DailyMotivationService {
  DailyMotivationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<DailyMotivation?> fetchToday({
    bool generateIfMissing = false,
    bool forceRegenerate = false,
  }) async {
    final today = _jamaicaDateKey();
    if (forceRegenerate) {
      try {
        await _invoke('generate-daily-motivation');
      } catch (_) {
        // Fall through to the latest published item if regeneration is unavailable.
      }
    }
    final data = await _client
        .from('daily_motivations')
        .select()
        .eq('publish_date', today)
        .eq('is_published', true)
        .eq('status', 'published')
        .limit(1)
        .maybeSingle();
    if (data != null) return DailyMotivation.fromMap(data);
    if (!generateIfMissing) return null;

    try {
      await _invoke('generate-daily-motivation');
      final generated = await _client
          .from('daily_motivations')
          .select()
          .eq('publish_date', today)
          .eq('is_published', true)
          .eq('status', 'published')
          .limit(1)
          .maybeSingle();
      return generated == null ? null : DailyMotivation.fromMap(generated);
    } catch (_) {
      return null;
    }
  }

  Future<DailyMotivation?> fetchById(String id) async {
    if (id.trim().isEmpty) return fetchToday();
    final data = await _client
        .from('daily_motivations')
        .select()
        .eq('id', id.trim())
        .maybeSingle();
    return data == null ? null : DailyMotivation.fromMap(data);
  }

  Future<List<DailyMotivation>> fetchRecent({int limit = 14}) async {
    final rows = await _client
        .from('daily_motivations')
        .select()
        .eq('is_published', true)
        .eq('status', 'published')
        .order('publish_date', ascending: false)
        .limit(limit);
    return rows
        .map<DailyMotivation>(
          (row) => DailyMotivation.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<List<DailyMotivation>> fetchAdminHistory({int limit = 60}) async {
    final rows = await _client
        .from('daily_motivations')
        .select()
        .order('publish_date', ascending: false)
        .limit(limit);
    return rows
        .map<DailyMotivation>(
          (row) => DailyMotivation.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<void> saveManual({
    String? id,
    required DateTime publishDate,
    required String title,
    required String message,
    required String scriptureReference,
    String? topic,
    required bool publish,
  }) async {
    final row = {
      if (id != null) 'id': id,
      'publish_date': publishDate.toIso8601String().substring(0, 10),
      'title': title.trim(),
      'message': message.trim(),
      'scripture_reference': scriptureReference.trim(),
      'topic': topic?.trim(),
      'source': 'manual',
      'status': publish ? 'published' : 'draft',
      'is_published': publish,
      'published_at': publish ? DateTime.now().toIso8601String() : null,
    };
    await _client
        .from('daily_motivations')
        .upsert(row, onConflict: 'publish_date');
  }

  Future<void> setPublished(String id, bool publish) async {
    await _client.from('daily_motivations').update({
      'status': publish ? 'published' : 'unpublished',
      'is_published': publish,
      'published_at': publish ? DateTime.now().toIso8601String() : null,
    }).eq('id', id);
  }

  Future<Map<String, dynamic>> _invoke(String functionName) async {
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: const {},
      ).timeout(const Duration(seconds: 18));
      final data = response.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] != null) throw Exception(map['error']);
        return map;
      }
    } catch (error, stackTrace) {
      if (SupabaseResilience.isTransientNetworkError(error)) {
        SupabaseResilience.logTransientNetworkError(
          'Daily Motivation $functionName',
          error,
          stackTrace,
        );
      }
      rethrow;
    }
    throw Exception('Unexpected response from Daily Word service.');
  }

  String _jamaicaDateKey() {
    final jamaicaNow = DateTime.now().toUtc().subtract(
          const Duration(hours: 5),
        );
    return DateTime(jamaicaNow.year, jamaicaNow.month, jamaicaNow.day)
        .toIso8601String()
        .substring(0, 10);
  }
}
