import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'app_experience_service.dart';

/// Only cumulative foreground seconds and infrequent survey events are stored.
/// Server-side per-install counters make retries and multiple devices safe.
class AppExperienceController extends ChangeNotifier {
  AppExperienceController({required this.backend, required this.platform});
  final ExperienceBackend backend;
  final String platform;
  final _watch = Stopwatch();
  Timer? _timer;
  String? userId;
  String deviceId = '';
  int localSeconds = 0, _session = 0;
  bool _disposed = false, _syncing = false, _foreground = true;
  Map<String, dynamic> server = {};
  final List<Map<String, dynamic>> _pending = [];
  Future<void> _writes = Future.value();
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool get eligible => server['eligible'] == true && _pending.isEmpty;
  String? get storeUrl =>
      server[platform == 'ios' ? 'ios_url' : 'android_url'] as String?;
  String get storeName => platform == 'ios' ? 'App Store' : 'Google Play';
  int get totalSeconds =>
      (server['state'] as Map?)?['active_seconds'] as int? ?? localSeconds;
  bool get initialized => deviceId.isNotEmpty && userId != null;
  String _key(String id) => 'app.experience.$id.v1';
  Future<void> initializeForUser(String? id) async {
    if (id == userId) return;
    _capture();
    final previousWrite = _persist();
    final session = ++_session;
    _timer?.cancel();
    _watch.stop();
    _watch.reset();
    userId = id;
    deviceId = '';
    localSeconds = 0;
    server = {};
    _pending.clear();
    _syncing = false;
    _notify();
    await previousWrite;
    if (_disposed || session != _session) return;
    if (id == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(id));
      final cached = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw));
      if (_disposed || session != _session) return;
      deviceId = cached['device_id'] as String? ?? const Uuid().v4();
      localSeconds = cached['seconds'] as int? ?? 0;
      _pending.addAll((cached['pending'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e)));
    } catch (_) {
      if (_disposed || session != _session) return;
      deviceId = const Uuid().v4();
    }
    if (_foreground) _watch.start();
    await _persist();
    if (_disposed || session != _session) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      final before = localSeconds;
      _capture();
      unawaited(_persist());
      if (_foreground &&
          (DateTime.now().difference(_lastSync).inMinutes >= 5 ||
              (before < 7200 && localSeconds >= 7200))) {
        unawaited(synchronize());
      }
    });
    await synchronize();
  }

  void _capture() {
    if (_watch.isRunning) {
      localSeconds += _watch.elapsed.inSeconds;
      _watch.reset();
    }
  }

  void setForeground(bool value) {
    _capture();
    _foreground = value;
    if (value && initialized) {
      _watch.start();
      unawaited(synchronize());
    } else {
      _watch.stop();
      unawaited(_persist());
      if (initialized) unawaited(synchronize());
    }
  }

  Future<void> _persist() async {
    final id = userId;
    if (id == null || deviceId.isEmpty) return;
    final value = jsonEncode(
        {'device_id': deviceId, 'seconds': localSeconds, 'pending': _pending});
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        await (await SharedPreferences.getInstance())
            .setString(_key(id), value);
      } catch (_) {}
    });
    await _writes;
  }

  Future<void> synchronize() async {
    if (!initialized || _syncing || _disposed) return;
    final session = _session, id = userId!;
    _capture();
    _syncing = true;
    _lastSync = DateTime.now();
    try {
      while (_pending.isNotEmpty) {
        final event = Map<String, dynamic>.from(_pending.first);
        final result =
            await backend.sync(id, deviceId, localSeconds, event: event);
        if (_disposed || session != _session) return;
        _pending.removeWhere((e) => e['id'] == event['id']);
        server = result;
        await _persist();
      }
      final result = await backend.sync(id, deviceId, localSeconds);
      if (_disposed || session != _session) return;
      server = result;
      _notify();
    } catch (_) {
      /* Retry later; optional surveys must never block the app. */
    } finally {
      if (session == _session) _syncing = false;
    }
  }

  Future<bool> claimPrompt() async {
    if (!eligible || !initialized || _syncing) return false;
    final id = userId!, session = _session;
    _capture();
    _syncing = true;
    try {
      final result = await backend.sync(id, deviceId, localSeconds, event: {
        'id': const Uuid().v4(),
        'kind': 'shown',
        'platform': platform
      });
      if (_disposed || session != _session) return false;
      server = result;
      _notify();
      return result['claimed'] == true;
    } catch (_) {
      return false;
    } finally {
      if (session == _session) _syncing = false;
    }
  }

  Future<void> record(String kind, {bool? response}) async {
    if (!initialized) return;
    _pending.add({
      'id': const Uuid().v4(),
      'kind': kind,
      'platform': platform,
      if (response != null) 'response': response
    });
    server = {...server, 'eligible': false};
    _notify();
    await _persist();
    await synchronize();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _capture();
    unawaited(_persist());
    _disposed = true;
    _session++;
    _timer?.cancel();
    _watch.stop();
    super.dispose();
  }
}
