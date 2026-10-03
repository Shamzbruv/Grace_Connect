import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tutorial_runtime.dart';
import 'tutorial_screen_scope.dart';

class TutorialAnchor extends StatefulWidget {
  const TutorialAnchor(
      {super.key,
      required this.id,
      required this.child,
      this.global = false,
      this.enabled = true});
  final String id;
  final Widget child;
  final bool global;
  final bool enabled;
  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final _token = Object();
  TutorialRuntime? _runtime;
  Object? _scope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runtime = context.read<TutorialRuntime?>();
    _scope = widget.global
        ? null
        : context
            .dependOnInheritedWidgetOfExactType<TutorialScopeData>()
            ?.token;
    _register();
  }

  void _register() {
    if (widget.enabled) {
      _runtime?.putAnchor(_token, _scope, widget.id, context);
    } else {
      _runtime?.removeAnchor(_token);
    }
  }

  @override
  void didUpdateWidget(TutorialAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  @override
  void dispose() {
    _runtime?.removeAnchor(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizeChangedLayoutNotifier(child: widget.child);
}

extension TutorialWidget on Widget {
  Widget tutorial(String id, {bool enabled = true}) =>
      TutorialAnchor(id: id, enabled: enabled, child: this);
  Widget tutorialReady(bool ready) =>
      TutorialReadiness(ready: ready, child: this);
  Widget tutorialScreen(String id, {bool ready = true}) =>
      TutorialScreenScope(screenId: id, ready: ready, child: this);
}

/// Place inside an async builder so loading/error placeholders cannot start a tour.
class TutorialReadiness extends StatefulWidget {
  const TutorialReadiness(
      {super.key, required this.ready, required this.child});
  final bool ready;
  final Widget child;
  @override
  State<TutorialReadiness> createState() => _TutorialReadinessState();
}

class _TutorialReadinessState extends State<TutorialReadiness> {
  final _token = Object();
  TutorialRuntime? _runtime;
  Object? _scope;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runtime = context.read<TutorialRuntime?>();
    _scope =
        context.dependOnInheritedWidgetOfExactType<TutorialScopeData>()?.token;
    _update();
  }

  void _update() {
    if (_scope != null) {
      _runtime?.putReadiness(_token, _scope!, widget.ready);
    }
  }

  @override
  void didUpdateWidget(TutorialReadiness oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _runtime?.removeReadiness(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
