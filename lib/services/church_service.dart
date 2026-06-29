import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_stats.dart';
import '../models/church_model.dart';
import '../models/service_schedule.dart';
import '../data/initial_churches.dart';
import '../services/church_stats_service.dart';

class ChurchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<Church?> getChurch(String churchId) async {
    try {
      final cleanChurchId = churchId.trim();
      if (cleanChurchId.isEmpty) return null;

      var doc = await _supabase
          .from('churches')
          .select()
          .eq('id', cleanChurchId)
          .maybeSingle();
      doc ??= await _supabase
          .from('churches')
          .select()
          .eq('placeId', cleanChurchId)
          .maybeSingle();
      if (doc != null) {
        return Church.fromMap(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<String>> fetchDenominations() async {
    try {
      final rows = await _supabase
          .from('denominations')
          .select('display_name')
          .eq('is_active', true)
          .order('sort_order')
          .limit(200);
      return rows
          .map<String>((row) => (row['display_name'] ?? '').toString().trim())
          .where((denomination) => denomination.isNotEmpty)
          .toList()
        ..sort();
    } catch (error) {
      debugPrint('Could not fetch denominations: $error');
      return const [];
    }
  }

  Future<List<Church>> fetchChurches({
    String? denomination,
    String? query,
    int limit = 50,
  }) async {
    try {
      var builder = _supabase
          .from('churches')
          .select()
          .eq('church_status', 'approved')
          .eq('public_visibility', true);

      final cleanDenomination = denomination?.trim();
      if (cleanDenomination != null && cleanDenomination.isNotEmpty) {
        builder = builder.eq('denomination', cleanDenomination);
      }

      final cleanQuery = query
          ?.trim()
          .replaceAll(RegExp(r'[%(),]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (cleanQuery != null && cleanQuery.isNotEmpty) {
        builder = builder.or(
          'name.ilike.%$cleanQuery%,'
          'address.ilike.%$cleanQuery%,'
          'denomination.ilike.%$cleanQuery%',
        );
      }

      final rows = await builder.order('name').limit(limit);
      return rows.map<Church>((row) => Church.fromMap(row)).toList();
    } catch (error) {
      debugPrint('Could not fetch churches: $error');
      return const [];
    }
  }

  Future<void> updateChurch(Church church) async {
    await _supabase.rpc('update_church_profile', params: {
      'p_church_id': church.placeId.isNotEmpty ? church.placeId : church.id,
      'p_name': church.name,
      'p_address': church.address,
      'p_denomination': church.denomination,
      'p_timezone': church.timezone,
      'p_about': church.about,
      'p_founded_year': church.foundedYear,
      'p_contact_email': church.contactEmail,
      'p_contact_phone': church.contactPhone,
      'p_website_url': church.websiteUrl,
      'p_service_times_note': church.serviceTimesNote,
    });
  }

  Stream<List<ServiceSchedule>> getSchedules(String churchId) {
    return _supabase
        .from('service_schedules')
        .stream(primaryKey: ['serviceId'])
        .eq('churchId', churchId)
        .map(
            (docs) => docs.map((doc) => ServiceSchedule.fromMap(doc)).toList());
  }

  Future<void> createSchedule(ServiceSchedule schedule) async {
    await _supabase.from('service_schedules').upsert(schedule.toMap());
  }

  Future<void> deleteSchedule(String churchId, String scheduleId) async {
    await _supabase
        .from('service_schedules')
        .delete()
        .eq('serviceId', scheduleId)
        .eq('churchId', churchId);
  }

  // --- Approved Church Search ---
  // Only server-approved, public churches are joinable. The local starter list is
  // deliberately excluded from membership search.

  /// Searches the approved public church directory.
  static Future<List<Map<String, String>>> searchChurches(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await Supabase.instance.client.rpc(
        'get_public_church_directory',
        params: {'search_query': query.trim()},
      );

      final rows = response is List ? response : const [];
      return rows.take(10).map<Map<String, String>>((row) {
        final data = Map<String, dynamic>.from(row as Map);
        return {
          'id': (data['placeId'] ?? data['id'] ?? '').toString(),
          'name': (data['name'] ?? '').toString(),
          'address': [
            (data['address'] ?? '').toString(),
            (data['parish'] ?? '').toString(),
          ].where((value) => value.trim().isNotEmpty).join(', '),
        };
      }).where((row) {
        return row['id']!.isNotEmpty && row['name']!.isNotEmpty;
      }).toList();
    } catch (e) {
      debugPrint('Approved church search error: $e');
      return const [];
    }
  }

  // Check if a church name already exists in Supabase
  Future<bool> checkChurchExists(String name) async {
    try {
      final result = await Supabase.instance.client
          .from('churches')
          .select('id')
          .ilike('name', name)
          .limit(1);
      return (result as List).isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Seed initial churches into Supabase (call once from Developer Console)
  Future<int> seedInitialChurches() async {
    int addedCount = 0;
    for (final churchName in initialChurches) {
      final exists = await checkChurchExists(churchName);
      if (!exists) {
        try {
          final placeId =
              'manual_${churchName.replaceAll(' ', '_').toLowerCase()}';
          await Supabase.instance.client.from('churches').insert({
            'id': placeId,
            'name': churchName,
            'placeId': placeId,
            'address': 'Jamaica',
            'denomination': 'New Testament Church of God',
            'status': 'verified',
            'createdAt': DateTime.now().toIso8601String(),
          });
          addedCount++;
        } catch (e) {
          debugPrint('Failed to seed $churchName: $e');
        }
      }
    }
    return addedCount;
  }

  // Register a manual church via Supabase
  Future<String?> registerManualChurch(String name, String address) async {
    final exists = await checkChurchExists(name);
    if (exists) return null;

    try {
      final placeId =
          'manual_${name.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
      final result = await Supabase.instance.client
          .from('churches')
          .insert({
            'id': placeId,
            'name': name,
            'placeId': placeId,
            'address': address,
            'denomination': 'New Testament Church of God',
            'status': 'pending',
            'createdAt': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      return result['id'] as String?;
    } catch (e) {
      debugPrint('Error registering church: $e');
      return null;
    }
  }

  // Transfer Ownership
  Future<void> transferOwnership(String churchId, String newOwnerUid) async {
    try {
      final cleanChurchId = churchId.trim();
      if (cleanChurchId.isEmpty || newOwnerUid.trim().isEmpty) {
        throw Exception('Missing church or new owner.');
      }

      final updated = await _supabase
          .from('churches')
          .update({'ownerUserId': newOwnerUid})
          .eq('id', cleanChurchId)
          .select('id');

      if (updated.isEmpty) {
        await _supabase
            .from('churches')
            .update({'ownerUserId': newOwnerUid})
            .eq('placeId', cleanChurchId)
            .select('id')
            .single();
      }
    } catch (e) {
      debugPrint('Supabase ownership transfer error: $e');
      rethrow;
    }
  }

  // Get Church Stats (still uses Firestore for analytics data)
  Future<ChurchStats> getStats(String churchId) async {
    return await ChurchStatsService().getStats(churchId);
  }

  // Update Stream Settings
  Future<void> updateStreamSettings(
      String churchId, String url, bool isLive) async {
    await Supabase.instance.client.from('churches').update({
      'liveStreamUrl': url,
      'isLive': isLive,
    }).eq('id', churchId);
  }
}
