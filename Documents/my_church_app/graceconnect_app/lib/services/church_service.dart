import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/church_stats.dart';
import '../models/church_model.dart';
import '../models/service_schedule.dart';
import '../data/initial_churches.dart';
import '../services/church_stats_service.dart';
// Note: ChurchService instance methods still use Firestore for non-auth features
// (schedules, stats, etc). Only searchChurches is migrated to local+Supabase.
import 'package:cloud_firestore/cloud_firestore.dart';

class ChurchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Church?> getChurch(String churchId) async {
    try {
      final doc = await _firestore.collection('churches').doc(churchId).get();
      if (doc.exists) {
        return Church.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateChurch(Church church) async {
    await _firestore
        .collection('churches')
        .doc(church.id)
        .update(church.toMap());
  }

  Stream<List<ServiceSchedule>> getSchedules(String churchId) {
    return _firestore
        .collection('churches')
        .doc(churchId)
        .collection('schedules')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ServiceSchedule.fromMap(doc.data()))
            .toList());
  }

  Future<void> createSchedule(ServiceSchedule schedule) async {
    await _firestore
        .collection('churches')
        .doc(schedule.churchId)
        .collection('schedules')
        .doc(schedule.serviceId)
        .set(schedule.toMap());
  }

  Future<void> deleteSchedule(String churchId, String scheduleId) async {
    await _firestore
        .collection('churches')
        .doc(churchId)
        .collection('schedules')
        .doc(scheduleId)
        .delete();
  }

  // --- Smart Church Search ---
  // Searches the local initial churches list (always available, no network needed)
  // PLUS any churches registered via the church signup screen in Supabase.

  static int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        int cost = (s[i] == t[j]) ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  /// Scores a church name against the search query.
  /// Returns a score (lower = better match) or 1000 if no match.
  static int _scoreMatch(String name, String address, String searchLower,
      List<String> searchWords) {
    final nameLower = name.toLowerCase();
    final addressLower = address.toLowerCase();

    if (nameLower == searchLower) return 0;
    if (nameLower.startsWith(searchLower)) return 10;
    if (nameLower.contains(searchLower)) return 20;

    // Fuzzy word-by-word matching
    final nameWords =
        nameLower.split(' ').where((w) => w.isNotEmpty).toList();
    int totalDistance = 0;
    int matchedWords = 0;

    for (String searchWord in searchWords) {
      int bestWordDist = 1000;
      for (String nameWord in nameWords) {
        int dist = _levenshteinDistance(searchWord, nameWord);
        int allowedTypos = (searchWord.length / 4).ceil().clamp(1, 2);
        if (dist <= allowedTypos) {
          if (dist < bestWordDist) bestWordDist = dist;
        } else if (nameWord.startsWith(searchWord)) {
          bestWordDist = 0;
        }
      }
      if (bestWordDist != 1000) {
        totalDistance += bestWordDist;
        matchedWords++;
      }
    }

    if (matchedWords > 0 &&
        matchedWords >= (searchWords.length / 2).floor()) {
      return 30 + totalDistance;
    }

    // Fallback: check address
    if (addressLower.contains(searchLower)) return 40;

    return 1000; // No match
  }

  /// Searches both the local initial churches list AND Supabase-registered churches.
  /// The local list always works — no Firestore permission issues.
  static Future<List<Map<String, String>>> searchChurches(String query) async {
    if (query.trim().isEmpty) return [];

    final searchLower = query.trim().toLowerCase();
    final searchWords =
        searchLower.split(' ').where((w) => w.isNotEmpty).toList();

    List<Map<String, dynamic>> scoredResults = [];
    final Set<String> addedNames = {}; // Prevent duplicates

    // 1. Search local initial churches list (always available, instant, no network)
    for (final churchName in initialChurches) {
      final score =
          _scoreMatch(churchName, 'Jamaica', searchLower, searchWords);
      if (score < 1000) {
        scoredResults.add({
          'score': score,
          'id': 'local_${churchName.replaceAll(' ', '_').toLowerCase()}',
          'name': churchName,
          'address': 'Jamaica',
        });
        addedNames.add(churchName.toLowerCase());
      }
    }

    // 2. Also search Supabase-registered churches (user-created via church signup)
    try {
      final response = await Supabase.instance.client
          .from('churches')
          .select('id, name, address, place_id');

      for (final row in (response as List)) {
        final name = (row['name'] as String?) ?? '';
        final address = (row['address'] as String?) ?? 'Jamaica';
        final id = (row['id'] as String?) ?? (row['place_id'] as String?) ?? '';

        if (addedNames.contains(name.toLowerCase())) continue; // Skip duplicates

        final score = _scoreMatch(name, address, searchLower, searchWords);
        if (score < 1000) {
          scoredResults.add({
            'score': score,
            'id': id,
            'name': name,
            'address': address,
          });
          addedNames.add(name.toLowerCase());
        }
      }
    } catch (e) {
      // Supabase query failed — local results still show, so this is non-fatal
      debugPrint('Supabase church search error: $e');
    }

    // Sort by score (best first) and return top 10
    scoredResults
        .sort((a, b) => (a['score'] as int).compareTo(b['score'] as int));

    return scoredResults
        .take(10)
        .map((item) => {
              'id': item['id'] as String,
              'name': item['name'] as String,
              'address': item['address'] as String,
            })
        .toList();
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
          await Supabase.instance.client.from('churches').insert({
            'name': churchName,
            'place_id': 'manual_${churchName.replaceAll(' ', '_').toLowerCase()}',
            'address': 'Jamaica',
            'denomination': 'New Testament Church of God',
            'status': 'verified',
            'created_at': DateTime.now().toIso8601String(),
            'members_count': 0,
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
      final result = await Supabase.instance.client.from('churches').insert({
        'name': name,
        'place_id':
            'manual_${name.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
        'address': address,
        'denomination': 'New Testament Church of God',
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'members_count': 1,
      }).select('id').single();

      return result['id'] as String?;
    } catch (e) {
      debugPrint('Error registering church: $e');
      return null;
    }
  }

  // Get Church Stats (still uses Firestore for analytics data)
  Future<ChurchStats> getStats(String churchId) async {
    return await ChurchStatsService().getStats(churchId);
  }

  // Update Stream Settings (still uses Firestore)
  Future<void> updateStreamSettings(
      String churchId, String url, bool isLive) async {
    await _firestore.collection('churches').doc(churchId).update({
      'liveStreamUrl': url,
      'isLive': isLive,
    });
  }
}
