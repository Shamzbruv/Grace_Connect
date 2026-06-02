import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  static const List<String> reportReasons = [
    'Harassment or bullying',
    'Hate speech',
    'Nudity or sexual content',
    'Violence or threats',
    'Scam or fraud',
    'Spam',
    'False information',
    'Inappropriate language',
    'Impersonation',
    'Other reason',
  ];

  Future<void> reportContent({
    required String churchId,
    required String contentType,
    required String reason,
    String? contentId,
    String? reportedUserId,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) async {
    final uid = _supabase.auth.currentUser?.id ?? '';
    if (uid.isEmpty || churchId.isEmpty || reason.trim().isEmpty) return;

    await _supabase.from('content_reports').insert({
      'church_id': churchId,
      'reporter_id': uid,
      'reported_user_id': reportedUserId,
      'content_type': contentType,
      'content_id': contentId,
      'reason': reason,
      'description':
          description?.trim().isEmpty == true ? null : description?.trim(),
      'metadata': metadata,
    });
  }

  Future<void> blockUser({
    required String churchId,
    required String blockedUserId,
    String? reason,
  }) async {
    final uid = _supabase.auth.currentUser?.id ?? '';
    if (uid.isEmpty || churchId.isEmpty || blockedUserId.isEmpty) return;

    await _supabase.from('user_blocks').upsert(
      {
        'church_id': churchId,
        'blocker_id': uid,
        'blocked_user_id': blockedUserId,
        'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
      },
      onConflict: 'blocker_id,blocked_user_id',
    );
  }

  Future<void> unblockUser(String blockedUserId) async {
    final uid = _supabase.auth.currentUser?.id ?? '';
    if (uid.isEmpty || blockedUserId.isEmpty) return;

    await _supabase
        .from('user_blocks')
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_user_id', blockedUserId);
  }

  Future<Set<String>> blockedUserIds() async {
    final uid = _supabase.auth.currentUser?.id ?? '';
    if (uid.isEmpty) return const {};

    final rows = await _supabase
        .from('user_blocks')
        .select('blocked_user_id')
        .eq('blocker_id', uid);

    return rows
        .map((row) => row['blocked_user_id']?.toString())
        .whereType<String>()
        .toSet();
  }
}
