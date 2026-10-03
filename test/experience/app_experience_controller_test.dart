import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grace_connect/experience/app_experience_controller.dart';
import 'package:grace_connect/experience/app_experience_service.dart';

class Backend implements ExperienceBackend {
  final calls = <({
    String user,
    String device,
    int seconds,
    Map<String, dynamic>? event
  })>[];
  bool offline = false;
  @override
  Future<Map<String, dynamic>> sync(String user, String device, int seconds,
      {Map<String, dynamic>? event}) async {
    calls.add((user: user, device: device, seconds: seconds, event: event));
    if (offline) throw StateError('offline');
    return {
      'eligible': seconds >= 7200 && event == null,
      'claimed': event?['kind'] == 'shown',
      'state': {'active_seconds': seconds},
      'android_url':
          'https://play.google.com/store/apps/details?id=love.graceconnect',
      'ios_url': null
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'cumulative device identity persists and never crosses signed-in accounts',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'app.experience.a.v1',
        jsonEncode({
          'device_id': '10000000-0000-4000-8000-000000000001',
          'seconds': 7200,
          'pending': []
        }));
    final backend = Backend();
    final controller =
        AppExperienceController(backend: backend, platform: 'android');
    addTearDown(controller.dispose);
    await controller.initializeForUser('a');
    expect(backend.calls.last.seconds, 7200);
    expect(controller.eligible, true);
    expect(controller.storeName, 'Google Play');
    final aDevice = controller.deviceId;
    await controller.initializeForUser('b');
    expect(controller.localSeconds, 0);
    expect(controller.deviceId, isNot(aDevice));
    await controller.initializeForUser('a');
    expect(controller.deviceId, aDevice);
    expect(controller.localSeconds, greaterThanOrEqualTo(7200));
    await controller.initializeForUser(null);
    expect(controller.initialized, false);
    expect(controller.eligible, false);
  });
  test('offline answers keep their event id until successfully retried',
      () async {
    final backend = Backend();
    final controller =
        AppExperienceController(backend: backend, platform: 'android');
    addTearDown(controller.dispose);
    await controller.initializeForUser('a');
    backend.offline = true;
    await controller.record('answered', response: false);
    final first = backend.calls.last.event!;
    expect(first['response'], false);
    backend.offline = false;
    await controller.synchronize();
    final retry =
        backend.calls.where((c) => c.event?['kind'] == 'answered').last.event!;
    expect(retry['id'], first['id']);
    expect(retry['response'], false);
    final prefs = await SharedPreferences.getInstance();
    expect(
        (jsonDecode(prefs.getString('app.experience.a.v1')!) as Map)['pending'],
        isEmpty);
  });
  test('rapid account changes keep the latest signed-in account', () async {
    final controller =
        AppExperienceController(backend: Backend(), platform: 'android');
    addTearDown(controller.dispose);
    await controller.initializeForUser('a');
    final first = controller.initializeForUser('b');
    final latest = controller.initializeForUser('a');
    await Future.wait([first, latest]);
    expect(controller.userId, 'a');
    expect(controller.initialized, true);
    final signingOut = controller.initializeForUser(null);
    final signingIn = controller.initializeForUser('c');
    await Future.wait([signingOut, signingIn]);
    expect(controller.userId, 'c');
    expect(controller.initialized, true);
  });
  test('iPhone invitations wait for a real store listing', () async {
    final controller =
        AppExperienceController(backend: Backend(), platform: 'ios');
    addTearDown(controller.dispose);
    await controller.initializeForUser('a');
    expect(controller.storeUrl, isNull);
    expect(controller.storeName, 'App Store');
  });
}
