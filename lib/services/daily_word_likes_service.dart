import 'package:supabase_flutter/supabase_flutter.dart';

class DailyWordEngagement {
  const DailyWordEngagement({required this.count, required this.liked});
  final int count;
  final bool liked;

  factory DailyWordEngagement.fromResponse(dynamic data) {
    if (data is! Map) {
      throw StateError('This Daily Word is no longer available.');
    }
    return DailyWordEngagement(
        count: ((data['like_count'] as num?)?.toInt() ?? 0)
            .clamp(0, 1 << 62)
            .toInt(),
        liked: data['liked'] == true);
  }
}

class DailyWordLikesService {
  DailyWordLikesService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<DailyWordEngagement> fetch(String id) async =>
      DailyWordEngagement.fromResponse(await _client.rpc(
          'get_daily_motivation_engagement',
          params: {'p_motivation_id': id}));

  Future<DailyWordEngagement> setLiked(String id, bool liked) async =>
      DailyWordEngagement.fromResponse(await _client.rpc(
          'set_daily_motivation_like',
          params: {'p_motivation_id': id, 'p_liked': liked}));
}
