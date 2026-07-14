import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/testimony.dart';
import '../models/user_profile.dart';
import 'notification_service.dart';

class TestimonyService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  Stream<List<Testimony>> watchTestimonies(String churchId) {
    return _supabase
        .from('testimonies')
        .stream(primaryKey: ['id'])
        .eq('church_id', churchId)
        .order('created_at', ascending: false)
        .map((rows) {
          final testimonies =
              rows.map((row) => Testimony.fromMap(row)).toList();
          testimonies.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return testimonies;
        });
  }

  Future<void> addTestimony({
    required UserProfile author,
    required String content,
    required bool isAnonymous,
  }) async {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) return;

    await _supabase.from('testimonies').insert({
      'church_id': author.churchId,
      'author_id': author.uid,
      'author_name':
          author.fullName.isNotEmpty ? author.fullName : author.email,
      'content': cleanContent,
      'is_anonymous': isAnonymous,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    final churchId = author.churchId.trim();
    if (churchId.isEmpty) return;

    final displayName =
        author.fullName.trim().isNotEmpty ? author.fullName.trim() : 'Someone';
    await _notificationService.sendNotification(
      'New testimony',
      isAnonymous
          ? 'Someone shared a testimony.'
          : '$displayName shared a testimony.',
      'church_$churchId',
      route: '/testimonies',
      type: 'testimony',
    );
  }

  Future<void> toggleReaction(String testimonyId, String emoji) async {
    await _supabase.rpc(
      'toggle_testimony_reaction',
      params: {
        'target_testimony_id': testimonyId,
        'reaction_emoji': emoji,
      },
    );
  }

  Future<void> deleteTestimony(String testimonyId) async {
    if (testimonyId.trim().isEmpty) return;
    await _supabase.from('testimonies').delete().eq('id', testimonyId.trim());
  }
}
