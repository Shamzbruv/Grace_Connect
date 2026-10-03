import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grace_connect/tutorial/tutorial_controller.dart';
import 'package:grace_connect/tutorial/tutorial_definition.dart';
import 'package:grace_connect/tutorial/tutorial_service.dart';
import 'package:grace_connect/tutorial/tutorial_state.dart';
import 'package:grace_connect/tutorial/tutorial_step.dart';
import 'package:grace_connect/tutorial/tutorial_storage.dart';
import 'package:grace_connect/tutorial/tutorial_registry.dart';

class MemoryStorage extends TutorialStorage {
  final data = <String, TutorialState>{};
  @override
  Future<TutorialState> load(String id) async => data[id] ?? TutorialState();
  @override
  Future<void> save(String id, TutorialState state) async {
    data[id] = state;
  }
}

class DeferredSync implements TutorialSync {
  final requests =
      <({String id, TutorialState state, Completer<TutorialState> done})>[];
  @override
  Future<TutorialState> synchronize(String id, TutorialState state) {
    final done = Completer<TutorialState>();
    requests.add((id: id, state: state, done: done));
    return done.future;
  }
}

const guide = TutorialDefinition('inbox',
    [TutorialStep('inbox.tools', 'Messages', 'Start a conversation.')]);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'cache is account scoped, persists dirty offline changes and fails closed on corruption',
      () async {
    final storage = TutorialStorage();
    await storage.save(
        'a', TutorialState(enabled: true, generation: 3, settingsDirty: true));
    expect((await storage.load('a')).generation, 3);
    expect((await storage.load('a')).settingsDirty, true);
    expect((await storage.load('b')).enabled, false);
    (await SharedPreferences.getInstance())
        .setString(storage.key('a'), 'broken');
    expect((await storage.load('a')).enabled, false);
  });
  test(
      'same generation unions history; remote restart dominates and new versions replay',
      () {
    const p = TutorialProgress(screenId: 'inbox', generation: 2);
    const other = TutorialProgress(
        screenId: 'events', generation: 2, status: 'dismissed');
    final local = TutorialState(
        enabled: true,
        generation: 2,
        progress: {p.key: p},
        progressDirty: true);
    final merged = local.merge(TutorialState(
        enabled: true, generation: 2, progress: {other.key: other}));
    expect(merged.hasSeen('inbox', 1), true);
    expect(merged.hasSeen('events', 1), true);
    expect(merged.hasSeen('inbox', 2), false);
    final restarted = merged.merge(TutorialState(enabled: true, generation: 3));
    expect(restarted.generation, 3);
    expect(restarted.hasSeen('inbox', 1), false);
    expect(restarted.progress.length, 2);
  });
  test(
      'restart and OFF to ON increment generation, retain history and skip is seen',
      () async {
    final storage = MemoryStorage()..data['a'] = TutorialState(enabled: true);
    final controller = TutorialController(storage: storage);
    addTearDown(controller.dispose);
    await controller.initializeForUser('a');
    controller.start(guide, guide.steps);
    await controller.skipCurrentScreen();
    expect(controller.isSeen('inbox', 1), true);
    await controller.restartAll();
    expect(controller.generation, 2);
    expect(controller.isSeen('inbox', 1), false);
    expect(controller.state.progress.length, 1);
    await controller.setEnabled(false);
    await controller.setEnabled(true);
    expect(controller.generation, 3);
    controller.start(guide, []);
    expect(controller.isSeen('inbox', 1), true);
    expect(controller.current, isNull);
  });
  test('account switch ignores old in-flight response and clears the guide',
      () async {
    final storage = MemoryStorage()
      ..data['a'] = TutorialState(enabled: true)
      ..data['b'] = TutorialState();
    final sync = DeferredSync();
    final c = TutorialController(storage: storage, service: sync);
    addTearDown(c.dispose);
    await c.initializeForUser('a');
    c.start(guide, guide.steps);
    await c.initializeForUser('b');
    sync.requests.first.done
        .complete(TutorialState(enabled: true, generation: 99));
    await Future<void>.delayed(Duration.zero);
    expect(c.userId, 'b');
    expect(c.generation, 1);
    expect(c.enabled, false);
    expect(c.current, isNull);
    sync.requests.last.done.complete(TutorialState());
    await Future<void>.delayed(Duration.zero);
  });
  test(
      'local progress and restart survive an older successful in-flight response',
      () async {
    final storage = MemoryStorage()..data['a'] = TutorialState(enabled: true);
    final sync = DeferredSync();
    final c = TutorialController(storage: storage, service: sync);
    addTearDown(c.dispose);
    await c.initializeForUser('a');
    c.start(guide, guide.steps);
    await c.completeCurrentScreen();
    await c.restartAll();
    sync.requests.first.done.complete(TutorialState(enabled: true));
    await Future<void>.delayed(Duration.zero);
    expect(c.generation, 2);
    expect(c.state.settingsDirty, true);
    expect(c.state.progress.length, 1);
    expect(sync.requests.length, 2);
    sync.requests.last.done
        .complete(TutorialState(enabled: true, generation: 2));
    await Future<void>.delayed(Duration.zero);
    expect(c.state.settingsDirty, false);
  });
  test(
      'offline failures keep pending progress and can retry without blocking guidance',
      () async {
    final storage = MemoryStorage()..data['a'] = TutorialState(enabled: true);
    final sync = DeferredSync();
    final c = TutorialController(storage: storage, service: sync);
    addTearDown(c.dispose);
    await c.initializeForUser('a');
    sync.requests.first.done.completeError(StateError('offline'));
    await Future<void>.delayed(Duration.zero);
    c.start(guide, guide.steps);
    await c.completeCurrentScreen();
    expect(c.state.progressDirty, true);
    final retry = c.synchronize();
    sync.requests.last.done.complete(c.state.copyWith(progressDirty: false));
    await retry;
    expect(c.isSeen('inbox', 1), true);
    expect(c.state.progressDirty, false);
  });
  test('role dashboards have isolated ids and tutorial targets are unique', () {
    expect(TutorialRegistry.dashboardId(['member']), 'dashboard.member');
    expect(TutorialRegistry.dashboardId(['pastor']), 'dashboard.pastor');
    for (final definition in TutorialRegistry.definitions.values) {
      expect(definition.steps.map((s) => s.targetId).toSet().length,
          definition.steps.length);
      expect(RegExp(r'^[a-z][a-z0-9_.]{0,79}$').hasMatch(definition.screenId),
          true);
    }
  });
}
