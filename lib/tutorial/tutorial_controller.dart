import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/haptic_service.dart';
import 'tutorial_analytics.dart';
import 'tutorial_definition.dart';
import 'tutorial_service.dart';
import 'tutorial_state.dart';
import 'tutorial_step.dart';
import 'tutorial_storage.dart';

/// Learning state only. Mounted widgets and geometry live in TutorialRuntime.
class TutorialController extends ChangeNotifier {
  TutorialController(
      {TutorialStorage? storage, this.service, TutorialAnalytics? analytics})
      : storage = storage ?? TutorialStorage(),
        analytics = analytics ?? TutorialAnalytics();
  final TutorialStorage storage;
  final TutorialSync? service;
  final TutorialAnalytics analytics;
  TutorialState state = TutorialState();
  String? userId;
  bool initialized = false;
  int _session = 0, _revision = 0, _suppression = 0;
  bool _disposed = false, _syncing = false, _hostBlocked = true;
  String? _visibleScreen, _deferredScreen;
  Future<void> _writes = Future.value();
  Timer? _syncTimer;
  TutorialDefinition? current;
  List<TutorialStep> steps = [];
  int activeStepIndex = 0;
  bool leaveMenuVisible = false;
  bool get enabled => state.enabled;
  int get generation => state.generation;
  String? get activeScreenId => current?.screenId;
  bool get temporarilySuppressed => _suppression > 0;
  bool get overlayVisible =>
      current != null &&
      enabled &&
      initialized &&
      !_hostBlocked &&
      !temporarilySuppressed;
  bool guiding(String screen) => overlayVisible && current?.screenId == screen;
  TutorialStep? get step => steps.isEmpty ? null : steps[activeStepIndex];
  bool isSeen(String screen, int version) => state.hasSeen(screen, version);

  Future<void> initializeForUser(String? id) async {
    if (userId == id && (initialized || id == null)) {
      return;
    }
    final session = ++_session;
    userId = id;
    initialized = false;
    state = TutorialState();
    _revision++;
    _syncTimer?.cancel();
    _syncing = false;
    _suppression = 0;
    _deferredScreen = null;
    _clearGuide();
    _emit();
    if (id == null) {
      return;
    }
    TutorialState cached;
    try {
      cached = await storage.load(id);
    } catch (_) {
      cached = TutorialState();
    }
    if (_disposed || session != _session) {
      return;
    }
    state = cached;
    initialized = true;
    _emit();
    unawaited(synchronize());
  }

  Future<void> _persist() async {
    final id = userId;
    if (id == null) {
      return;
    }
    final snapshot = state;
    // Serialize snapshots so a slow older write cannot overwrite a restart.
    _writes = _writes.catchError((Object _) {}).then((_) async {
      try {
        await storage.save(id, snapshot);
      } catch (_) {/* best effort */}
    });
    await _writes;
  }

  void _changed() {
    _revision++;
    _emit();
    unawaited(_persist());
    _syncTimer?.cancel();
    if (service != null) {
      _syncTimer = Timer(
          const Duration(milliseconds: 600), () => unawaited(synchronize()));
    }
  }

  Future<void> synchronize() async {
    if (_syncing ||
        service == null ||
        !initialized ||
        userId == null ||
        _disposed) {
      return;
    }
    final id = userId!, session = _session, revision = _revision;
    final snapshot = state;
    _syncing = true;
    var success = false;
    try {
      final remote = await service!.synchronize(id, snapshot);
      if (_disposed || session != _session) {
        return;
      }
      state = state.merge(remote, acknowledged: revision == _revision);
      if (!enabled ||
          (current != null && isSeen(current!.screenId, current!.version))) {
        _clearGuide();
      }
      _emit();
      await _persist();
      success = true;
    } catch (error) {
      debugPrint('Tutorial sync deferred (${error.runtimeType}).');
    } finally {
      if (!_disposed && session == _session) {
        _syncing = false;
        // Retry changes made during an in-flight successful write, not failures
        // in a polling loop. Offline work retries on resume or the next change.
        if (success && revision != _revision) unawaited(synchronize());
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value && !enabled) {
      await restartAll();
      return;
    }
    if (value == enabled) {
      return;
    }
    state = state.copyWith(enabled: value, settingsDirty: true);
    _clearGuide();
    _changed();
    analytics.event('tutorial_disabled');
  }

  Future<void> restartAll() async {
    // Restart from Settings applies on the next visit, without interrupting
    // the switch or confirmation the person is currently using.
    _deferredScreen = _visibleScreen;
    state = state.copyWith(
        enabled: true,
        generation: generation + 1,
        settingsDirty: true,
        progressDirty: false);
    _clearGuide();
    _changed();
    analytics.event('tutorial_restarted');
  }

  void start(TutorialDefinition definition, List<TutorialStep> available) {
    if (!initialized ||
        !enabled ||
        definition.screenId == _deferredScreen ||
        temporarilySuppressed ||
        isSeen(definition.screenId, definition.version)) {
      return;
    }
    if (current?.screenId == definition.screenId &&
        current?.version == definition.version) {
      return;
    }
    current = definition;
    steps = List.of(available);
    activeStepIndex = 0;
    leaveMenuVisible = false;
    if (steps.isEmpty) {
      unawaited(completeCurrentScreen());
      return;
    }
    analytics.event('tutorial_started',
        definition: current, count: steps.length);
    _viewed();
    _emit();
  }

  void screenChanged(String? id) {
    if (id != null && id != _visibleScreen) {
      _deferredScreen = null;
      _visibleScreen = id;
    }
    if (id != null && id != activeScreenId) {
      _clearGuide();
      _emit();
    }
  }

  void setHostBlocked(bool value) {
    if (_hostBlocked == value) {
      return;
    }
    _hostBlocked = value;
    _emit();
  }

  void next() {
    if (current == null) {
      return;
    }
    HapticService.selection();
    if (activeStepIndex + 1 >= steps.length) {
      unawaited(completeCurrentScreen());
      return;
    }
    activeStepIndex++;
    _viewed();
    _emit();
  }

  void previous() {
    if (activeStepIndex == 0) {
      return;
    }
    HapticService.selection();
    activeStepIndex--;
    _viewed();
    _emit();
  }

  void removeMissingTarget(String target) {
    if (current == null) {
      return;
    }
    steps = steps.where((s) => s.targetId != target).toList();
    if (steps.isEmpty || activeStepIndex >= steps.length) {
      unawaited(completeCurrentScreen());
      return;
    }
    _viewed();
    _emit();
  }

  void showLeaveMenu([bool show = true]) {
    leaveMenuVisible = show;
    _emit();
  }

  Future<void> completeCurrentScreen() => _finish('completed');
  Future<void> skipCurrentScreen() => _finish('dismissed');
  Future<void> disableTutorials() => setEnabled(false);
  Future<void> _finish(String status) async {
    final definition = current;
    if (definition == null) {
      return;
    }
    final item = TutorialProgress(
        screenId: definition.screenId,
        generation: generation,
        version: definition.version,
        status: status,
        stepReached:
            status == 'completed' ? steps.length : activeStepIndex + 1);
    state = state.copyWith(
        progress: {...state.progress, item.key: item}, progressDirty: true);
    analytics.event(
        status == 'completed'
            ? 'tutorial_completed'
            : 'tutorial_screen_dismissed',
        definition: definition,
        step: item.stepReached,
        count: steps.length);
    _clearGuide();
    _changed();
  }

  void suppress() {
    _suppression++;
    _emit();
  }

  void resume() {
    if (_suppression > 0) {
      _suppression--;
      _emit();
    }
  }

  Future<T> during<T>(Future<T> Function() action) async {
    suppress();
    try {
      return await action();
    } finally {
      resume();
    }
  }

  void _viewed() => analytics.event('tutorial_step_viewed',
      definition: current, step: activeStepIndex + 1, count: steps.length);
  void _clearGuide() {
    current = null;
    steps = [];
    activeStepIndex = 0;
    leaveMenuVisible = false;
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    _syncTimer?.cancel();
    super.dispose();
  }
}
