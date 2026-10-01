import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_connect/services/reel_service.dart';
import 'package:grace_connect/models/direct_message.dart';

void main() {
  const actor = '00000000-0000-4000-8000-000000000001';
  const reelId = '00000000-0000-4000-8000-000000000002';
  late SupabaseClient client;
  final requests = <http.Request>[];
  var denyWrites = false;
  setUp(() async {
    requests.clear();
    denyWrites = false;
    client = SupabaseClient('https://example.invalid', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      if (request.url.path.endsWith('/token')) {
        String part(Object value) => base64Url
            .encode(utf8.encode(jsonEncode(value)))
            .replaceAll('=', '');
        return http.Response(
            jsonEncode({
              'access_token': '${part({'alg': 'HS256'})}.${part({
                    'sub': actor,
                    'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
                  })}.test',
              'refresh_token': 'test-only',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'created_at': '2026-09-30T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {}
              },
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      requests.add(request);
      if (request.url.path.endsWith('/get_reel_grace_detail')) {
        return http.Response('null', 200, request: request);
      }
      if (request.url.path.endsWith('/get_reel_grace_profile')) {
        return http.Response(
            jsonEncode({
              'reels': [
                {
                  'id': reelId,
                  'author_id': actor,
                  'caption': 'Profile reel',
                  'published_at': '2026-09-30T00:00:00Z'
                }
              ],
              'next_cursor': {
                'id': reelId,
                'published_at': '2026-09-30T00:00:00Z'
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request);
      }
      return denyWrites
          ? http.Response('{"code":"42501","message":"denied"}', 403,
              request: request)
          : http.Response('', 204, request: request);
    }));
    await client.auth.signInWithPassword(
        email: 'test@example.invalid', password: 'test-only');
  });
  tearDown(() async => client.dispose());

  test('likes and saves use authenticated identity and idempotent inserts',
      () async {
    final service = ReelService(client: client);
    expect(await service.toggleLike(reelId, liked: true), isTrue);
    expect(await service.toggleSave(reelId, saved: true), isTrue);
    for (final request in requests) {
      expect(jsonDecode(request.body)['user_id'], actor);
      expect(
          request.headers['prefer'], contains('resolution=ignore-duplicates'));
    }
    expect(
        requests.first.url.queryParameters['on_conflict'], 'reel_id,user_id');
    expect(requests.last.url.queryParameters['on_conflict'],
        'user_id,entity_type,entity_id');
  });
  test('rejected interactions report failure so optimistic UI can roll back',
      () async {
    denyWrites = true;
    final service = ReelService(client: client);
    expect(await service.toggleLike(reelId, liked: true), isFalse);
    expect(await service.toggleSave(reelId, saved: true), isFalse);
  });
  test(
      'profile paging passes its cursor and inaccessible detail stays unavailable',
      () async {
    final service = ReelService(client: client);
    final first = await service.fetchProfile(actor);
    expect(first.reels.single.id, reelId);
    await service.fetchProfile(actor, cursor: first.nextCursor);
    expect(jsonDecode(requests.last.body)['p_cursor'], first.nextCursor);
    expect(jsonDecode(requests.last.body)['p_limit'], 12);
    expect(await service.fetchDetail(reelId), isNull);
  });
  test(
      'shared messages retain an ID reference without requiring a permanent media URL',
      () {
    final message = DirectMessage.fromMap({
      'id': 'm',
      'shared_content': {'kind': 'reel', 'id': reelId}
    });
    expect(message.sharedContent, {'kind': 'reel', 'id': reelId});
    expect(message.mediaUrl, isNull);
  });
}
