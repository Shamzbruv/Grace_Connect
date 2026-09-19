import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/reel.dart';

/// Reel feed and media access.
///
/// The bucket is private, so a reel's bytes are reachable only through a
/// short-lived signed URL. Two consequences shape this class:
///
/// 1. Signing is batched per page. Signing per reel would put a network round
///    trip in front of every swipe.
/// 2. The cache is keyed by reel id, never by URL. A re-signed URL is a
///    different string for the same bytes; keying on the URL would defeat
///    every layer of caching below this one and re-download video the device
///    already has.
///
/// Signed URLs live here in memory only. They are never written to disk and
/// never stored on a Reel.
class ReelService {
  ReelService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final Map<String, ReelMedia> _media = {};
  Future<void>? _inFlightSigning;

  Future<ReelPage> fetchFeed({
    String mode = 'discover',
    Map<String, dynamic>? cursor,
    int limit = 12,
  }) async {
    final data = await _client.rpc('get_reel_grace_feed', params: {
      'p_mode': mode,
      'p_cursor': cursor,
      'p_limit': limit,
    });
    if (data is! Map) return const ReelPage(reels: []);
    final envelope = Map<String, dynamic>.from(data);
    final reels = (envelope['reels'] as List? ?? const [])
        .map((row) => Reel.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    final next = envelope['next_cursor'];
    return ReelPage(
      reels: reels,
      nextCursor: next is Map ? Map<String, dynamic>.from(next) : null,
    );
  }

  ReelMedia? cachedMedia(String reelId) {
    final media = _media[reelId];
    if (media == null || media.isExpired) return null;
    return media;
  }

  /// Signs everything the page needs in one call. Reels that already hold a
  /// URL with comfortable time left are skipped, so paging back and forth
  /// does not re-sign what is already in hand.
  Future<void> ensureMedia(Iterable<String> reelIds) async {
    final needed = reelIds.where((id) {
      final media = _media[id];
      return media == null || media.needsRefresh;
    }).toList(growable: false);
    if (needed.isEmpty) return;

    // Collapse concurrent requests: a swipe burst must not fire several
    // signing calls for overlapping windows.
    final pending = _inFlightSigning;
    if (pending != null) {
      await pending;
      final stillNeeded = needed.where((id) {
        final media = _media[id];
        return media == null || media.needsRefresh;
      }).toList(growable: false);
      if (stillNeeded.isEmpty) return;
    }

    final work = _signBatch(needed);
    _inFlightSigning = work;
    try {
      await work;
    } finally {
      if (identical(_inFlightSigning, work)) _inFlightSigning = null;
    }
  }

  Future<void> _signBatch(List<String> reelIds) async {
    try {
      final response = await _client.functions.invoke(
        'sign-reel-playback',
        body: {'reel_ids': reelIds},
      );
      final data = response.data;
      if (data is! Map) return;
      final envelope = Map<String, dynamic>.from(data);
      final expiresAt =
          DateTime.tryParse(envelope['expires_at']?.toString() ?? '') ??
              DateTime.now().add(const Duration(minutes: 30));
      for (final entry in (envelope['media'] as List? ?? const [])) {
        final row = Map<String, dynamic>.from(entry as Map);
        final id = row['reel_id']?.toString();
        if (id == null) continue;
        _media[id] = ReelMedia(
          videoUrl: row['video_url']?.toString(),
          posterUrl: row['poster_url']?.toString(),
          expiresAt: expiresAt,
        );
      }
      // Ids the server did not return are ones this viewer may not see. They
      // are deliberately left without media rather than retried.
    } catch (error) {
      debugPrint('Reel playback signing failed: $error');
    }
  }

  /// Re-signs a single reel whose URL lapsed mid-session.
  Future<ReelMedia?> refreshMedia(String reelId) async {
    _media.remove(reelId);
    await _signBatch([reelId]);
    return _media[reelId];
  }

  void forget(String reelId) => _media.remove(reelId);

  void clearMedia() => _media.clear();

  Future<bool> toggleLike(String reelId, {required bool liked}) async {
    try {
      if (liked) {
        await _client.from('reel_likes').insert({'reel_id': reelId});
      } else {
        await _client.from('reel_likes').delete().eq('reel_id', reelId);
      }
      return true;
    } catch (error) {
      debugPrint('Reel like failed: $error');
      return false;
    }
  }

  Future<bool> toggleSave(String reelId, {required bool saved}) async {
    try {
      if (saved) {
        await _client.from('social_saved_items').insert({
          'entity_type': 'reel',
          'entity_id': reelId,
        });
      } else {
        await _client
            .from('social_saved_items')
            .delete()
            .eq('entity_type', 'reel')
            .eq('entity_id', reelId);
      }
      return true;
    } catch (error) {
      debugPrint('Reel save failed: $error');
      return false;
    }
  }

  Future<void> markNotInterested(String reelId) async {
    try {
      await _client.from('reel_user_feedback').insert({
        'reel_id': reelId,
        'feedback_type': 'not_interested',
      });
    } catch (error) {
      debugPrint('Reel feedback failed: $error');
    }
  }

  Future<bool> deleteReel(String reelId) async {
    try {
      final response = await _client.functions
          .invoke('delete-reel', body: {'reel_id': reelId});
      final data = response.data;
      return data is Map && data['deleted'] == true;
    } catch (error) {
      debugPrint('Reel delete failed: $error');
      return false;
    }
  }
}
