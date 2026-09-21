import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:grace_connect/services/church_service.dart';
import 'package:grace_connect/services/analytics_service.dart';
import 'package:grace_connect/services/haptic_service.dart';
import 'package:grace_connect/services/bible_streak_service.dart';
import 'package:grace_connect/screens/bible/bible_search_delegate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('church logos upload to the actual church folder with unique paths',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://example.invalid', 'test-key',
        httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response('{"Key":"church_media/test-logo"}', 200,
          headers: {'content-type': 'application/json'});
    }));
    final service = ChurchService(client: client);
    final first = await service.uploadChurchLogo(
        churchId: ' church_a ',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
        fileExtension: 'PNG');
    final second = await service.uploadChurchLogo(
        churchId: 'church_a',
        bytes: Uint8List.fromList([137, 80, 78, 71]),
        fileExtension: 'png');
    expect(
        first,
        startsWith(
            'https://example.invalid/storage/v1/object/public/church_media/church_a/logo_'));
    expect(second, isNot(first));
    expect(requests, hasLength(2));
    expect(
        requests.first.url.path, matches(r'/church_a/logo_[a-f0-9-]+\.png$'));
    expect(requests.first.headers['content-type'],
        contains('multipart/form-data'));
    expect(String.fromCharCodes(requests.first.bodyBytes),
        contains('content-type: image/png'));
    await client.dispose();
  });

  test('invalid church logo input never reaches storage', () async {
    var calls = 0;
    final client = SupabaseClient('https://example.invalid', 'test-key',
        httpClient: MockClient((request) async {
      calls++;
      return http.Response('{}', 500);
    }));
    final service = ChurchService(client: client);
    expect(
        await service.uploadChurchLogo(
            churchId: '../other',
            bytes: Uint8List.fromList([1]),
            fileExtension: 'png'),
        isNull);
    expect(
        await service.uploadChurchLogo(
            churchId: 'church',
            bytes: Uint8List.fromList([1]),
            fileExtension: 'svg'),
        isNull);
    expect(calls, 0);
    await client.dispose();
  });

  test('analytics strips route credentials and uses supported parameter types',
      () {
    expect(
        Analytics.screenNameForRoute(const RouteSettings(
          name: '/auth-callback?access_token=secret#refresh_token=other',
        )),
        isNull);
    expect(
        Analytics.screenNameForRoute(const RouteSettings(
          name: '/community_post?entityId=private-identifier',
        )),
        '/community_post');
    expect(
        Analytics.screenNameForRoute(const RouteSettings(
          name: '/profile/some-person?email=private@example.org',
        )),
        '/profile');
    expect(
        Analytics.cleanParameters({
          'yes': true,
          'no': false,
          'score': 17,
          'bad': double.nan,
          'query': null,
          'object': Object(),
        }),
        {'yes': 1, 'no': 0, 'score': 17});
  });

  test('explicit numbered books never resolve a different numbered book', () {
    expect(
        BiblePassageSearch.search('2 tim').map((e) => e.book), ['2 Timothy']);
    expect(BiblePassageSearch.search('1 john 3:16').map((e) => e.book),
        ['1 John']);
    expect(BiblePassageSearch.search('John 0'), isEmpty);
    expect(BiblePassageSearch.search('John 3:0'), isEmpty);
    expect(BiblePassageSearch.search('3:16'), isEmpty);
  });

  test('streak history distinguishes an expired streak from a current one', () {
    final ranking = BibleStreakRanking.fromMap({
      'entries': [
        {
          'user_id': 'u',
          'user_name': 'Member',
          'streak_count': 40,
          'is_viewer': true,
          'is_current': false
        }
      ],
      'viewer': {
        'rank': 28,
        'streak_count': 40,
        'total': 100,
        'is_current': false
      },
    }, RankingScope.global);
    expect(ranking.viewerIsCurrent, false);
    expect(ranking.entries.single.isCurrent, false);
    expect(ranking.viewerRank, 28);
  });

  test(
      'haptic opt-out includes the test action and async failure stays contained',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var buzzes = 0;
    var fallbacks = 0;
    messenger.setMockMethodCallHandler(const MethodChannel('vibration'),
        (call) async {
      if (call.method == 'hasVibrator' ||
          call.method == 'hasAmplitudeControl') {
        return true;
      }
      if (call.method == 'vibrate') {
        buzzes++;
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') fallbacks++;
      return null;
    });
    SharedPreferences.setMockInitialValues({'haptics_enabled': false});
    await HapticService.load(
      vibratorProbe: () async => true,
      amplitudeProbe: () async => true,
    );
    HapticService.light();
    await HapticService.test();
    expect(buzzes, 0);
    expect(fallbacks, 0);
    HapticService.setEnabled(true);
    await HapticService.test();
    expect(buzzes, 1);
    expect(fallbacks, 1);
    HapticService.setEnabled(false);
    messenger.setMockMethodCallHandler(const MethodChannel('vibration'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
