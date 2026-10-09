import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_connect/services/saved_items_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const actor = '00000000-0000-4000-8000-000000000001';
  const reel = '00000000-0000-4000-8000-000000000002';
  late SupabaseClient client;
  final requests = <http.Request>[];
  var offline = false;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests.clear();
    offline = false;
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
                'created_at': '2026-10-08T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {}
              }
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      requests.add(request);
      if (offline) {
        return http.Response('{"code":"42501","message":"denied"}', 403,
            request: request);
      }
      if (request.url.path.endsWith('/get_my_saved_items')) {
        return http.Response(
            jsonEncode([
              {
                'id': 'save',
                'entity_type': 'reel',
                'entity_id': reel,
                'is_available': true,
                'metadata': {
                  'title': 'Reel by Creator',
                  'subtitle': 'Caption',
                  'media_type': 'reel'
                }
              },
              {
                'id': 'missing',
                'entity_type': 'reel',
                'entity_id': 'gone',
                'is_available': false,
                'metadata': {'title': 'Reel unavailable', 'subtitle': ''}
              }
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('', 204, request: request);
    }));
    await client.auth.signInWithPassword(
        email: 'test@example.invalid', password: 'test-only');
  });
  tearDown(() async => client.dispose());

  test('Saved loads current reel details and respects unavailable metadata',
      () async {
    final items = await SavedItemsService(client: client).fetchSavedItems();
    expect(requests.single.url.path, endsWith('/get_my_saved_items'));
    expect(items.first.title, 'Reel by Creator');
    expect(items.first.entityId, reel);
    expect(items.first.isAvailable, isTrue);
    expect(items.last.isAvailable, isFalse);
    expect(items.last.subtitle, isEmpty);
  });
  test(
      'failed loading and server removal are errors, never empty/success responses',
      () async {
    offline = true;
    final service = SavedItemsService(client: client);
    await expectLater(
        service.fetchSavedItems(), throwsA(isA<PostgrestException>()));
    await expectLater(service.unsave(entityType: 'reel', entityId: reel),
        throwsA(isA<PostgrestException>()));
    expect(requests.last.url.queryParameters['user_id'], 'eq.$actor');
    expect(requests.last.url.queryParameters['entity_id'], 'eq.$reel');
  });
  test(
      'a local-only bookmark can be removed offline without pretending to delete server data',
      () async {
    offline = true;
    final service = SavedItemsService(client: client);
    await service.save(
        entityType: 'community_post',
        entityId: 'local-post',
        title: 'Offline save');
    expect((await service.fetchSavedItems()).single.id, startsWith('local_'));
    requests.clear();
    await service.unsave(
        entityType: 'community_post', entityId: 'local-post', localOnly: true);
    expect(requests, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('local_social_saved_items_$actor'), isEmpty);
  });
}
