import 'package:flutter/material.dart';

class TutorialScene {
  TutorialScene(this.token, this.screenId, this.route, this.visible);
  final Object token;
  final String screenId;
  final ModalRoute<dynamic>? route;
  final bool visible;
  bool get eligible =>
      visible &&
      (route == null ||
          (route!.isCurrent &&
              (route!.animation == null ||
                  route!.animation!.status == AnimationStatus.completed)));
}

/// UI-owned registrations are separate from account progress and never persisted.
class TutorialRuntime extends ChangeNotifier {
  final Map<Object, TutorialScene> scenes = {};
  final Map<Object, ({Object scope, bool ready})> readiness = {};
  final Map<Object, ({Object? scope, String id, BuildContext context})>
      anchors = {};
  TutorialScene? get active {
    for (final scene in scenes.values.toList().reversed) {
      if (scene.eligible &&
          !readiness.values
              .any((item) => item.scope == scene.token && !item.ready)) {
        return scene;
      }
    }
    return null;
  }

  void putScene(TutorialScene scene) {
    final old = scenes[scene.token];
    scenes[scene.token] = scene;
    if (old?.screenId != scene.screenId ||
        old?.route != scene.route ||
        old?.visible != scene.visible) {
      changed();
    }
  }

  void removeScene(Object token) {
    if (scenes.remove(token) != null) changed();
  }

  void putReadiness(Object token, Object scope, bool ready) {
    final next = (scope: scope, ready: ready);
    if (readiness[token] == next) {
      return;
    }
    readiness[token] = next;
    changed();
  }

  void removeReadiness(Object token) {
    if (readiness.remove(token) != null) changed();
  }

  void putAnchor(Object token, Object? scope, String id, BuildContext context) {
    final next = (scope: scope, id: id, context: context);
    if (anchors[token] == next) {
      return;
    }
    anchors[token] = next;
    changed();
  }

  void removeAnchor(Object token) {
    if (anchors.remove(token) != null) changed();
  }

  BuildContext? target(Object scope, String id) {
    for (final item in anchors.values.toList().reversed) {
      if (item.id != id || !item.context.mounted) continue;
      if (item.scope == scope) {
        return item.context;
      }
      if (item.scope == null &&
          (ModalRoute.of(item.context)?.isCurrent ?? true)) {
        return item.context;
      }
    }
    return null;
  }

  bool _pending = false, _disposed = false;
  void changed() {
    if (_pending || _disposed) {
      return;
    }
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    anchors.clear();
    scenes.clear();
    super.dispose();
  }
}

class TutorialNavigationObserver extends NavigatorObserver {
  TutorialNavigationObserver(this.runtime);
  final TutorialRuntime runtime;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      runtime.changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      runtime.changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      runtime.changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      runtime.changed();
}
