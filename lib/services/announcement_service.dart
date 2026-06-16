import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/announcement.dart';
import '../models/user_profile.dart';
import 'ministry_service.dart';
import 'notification_service.dart';

class AnnouncementService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _table = 'announcements';
  static const Duration _realtimeQuietTimeout = Duration(seconds: 18);
  final MinistryService _ministryService = MinistryService();

  bool canPublish(UserProfile? user) {
    return user?.capabilities.canPublishAnnouncements == true;
  }

  Future<bool> canPublishForUser(UserProfile? user) {
    return _ministryService.canPublishAnnouncements(user);
  }

  Future<List<Announcement>> fetchAnnouncements(String churchId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _publishDueAnnouncements();
    final data = await _supabase
        .from(_table)
        .select()
        .eq('church_id', churchId)
        .or('expires_at.is.null,expires_at.gt.$now')
        .or('scheduled_at.is.null,scheduled_at.lte.$now')
        .order('created_at', ascending: false)
        .limit(100);

    return _normalizeAnnouncements(data);
  }

  Stream<List<Announcement>> watchAnnouncements(String churchId) async* {
    var lastKnown = <Announcement>[];

    try {
      lastKnown = await fetchAnnouncements(churchId);
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load announcements before realtime: $error');
    }

    try {
      await for (final announcements
          in _announcementsRealtime(churchId).timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) => sink.add(lastKnown),
      )) {
        lastKnown = announcements;
        yield announcements;
      }
    } catch (error) {
      debugPrint(
          'Announcement realtime unavailable, keeping last known data: $error');
      if (lastKnown.isNotEmpty) {
        yield lastKnown;
      }
    }
  }

  Stream<List<Announcement>> _announcementsRealtime(String churchId) {
    return _supabase
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('church_id', churchId)
        .order('created_at', ascending: false)
        .limit(100)
        .map(_normalizeAnnouncements);
  }

  Future<void> createAnnouncement({
    required UserProfile author,
    required String title,
    required String body,
    String priority = 'normal',
    String? ministryId,
    String ministryName = '',
    DateTime? expiresAt,
    DateTime? scheduledAt,
    String? linkUrl,
    String? locationName,
    String? locationAddress,
    double? locationLatitude,
    double? locationLongitude,
    String? googlePlaceId,
  }) async {
    final canPublishAnnouncement = canPublish(author) ||
        await _ministryService.canPublishAnnouncements(author);

    if (!canPublishAnnouncement) {
      throw Exception('You do not have permission to publish announcements.');
    }

    if (author.churchId.isEmpty) {
      throw Exception('Join a church before publishing announcements.');
    }

    await _supabase.from(_table).insert(
          Announcement(
            id: '',
            churchId: author.churchId,
            authorId: author.uid,
            authorName: author.fullName.isNotEmpty
                ? author.fullName
                : (author.email.isNotEmpty ? author.email : 'Grace Connect'),
            title: title,
            body: body,
            priority: priority,
            ministryId: ministryId,
            ministryName: ministryName,
            createdAt: DateTime.now(),
            expiresAt: expiresAt,
            scheduledAt: scheduledAt,
            linkUrl: linkUrl,
            locationName: locationName,
            locationAddress: locationAddress,
            locationLatitude: locationLatitude,
            locationLongitude: locationLongitude,
            googlePlaceId: googlePlaceId,
          ).toMap(),
        );

    if (scheduledAt == null || !scheduledAt.isAfter(DateTime.now())) {
      unawaited(
        NotificationService().sendNotification(
          title,
          body,
          'church_${author.churchId}',
          route: '/announcements',
          type: 'announcement',
        ),
      );
    }
  }

  Future<void> markAnnouncementNotificationsRead(String userId) async {
    await NotificationService().markRouteAsRead(userId, '/announcements');
  }

  List<Announcement> _normalizeAnnouncements(dynamic rows) {
    final normalized = (rows as List<dynamic>)
        .map((row) => Announcement.fromMap(Map<String, dynamic>.from(row)))
        .where((announcement) {
      final expiresAt = announcement.expiresAt;
      final scheduledAt = announcement.scheduledAt;
      final now = DateTime.now();
      return (expiresAt == null || expiresAt.isAfter(now)) &&
          (scheduledAt == null || !scheduledAt.isAfter(now));
    }).toList();

    normalized.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return normalized;
  }

  Future<void> _publishDueAnnouncements() async {
    try {
      await _supabase.rpc('publish_due_announcements');
    } catch (error) {
      debugPrint('Scheduled announcement publish skipped: $error');
    }
  }
}
