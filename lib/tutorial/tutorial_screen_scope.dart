import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tutorial_controller.dart';
import 'tutorial_runtime.dart';

/// Explicit visibility is essential for PageView/IndexedStack children.
class TutorialVisibility extends InheritedWidget {
  const TutorialVisibility(
      {super.key, required this.visible, required super.child});
  final bool visible;
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TutorialVisibility>()
          ?.visible ??
      true;
  @override
  bool updateShouldNotify(TutorialVisibility oldWidget) =>
      visible != oldWidget.visible;
}

class TutorialScopeData extends InheritedWidget {
  const TutorialScopeData(
      {super.key, required this.token, required super.child});
  final Object token;
  @override
  bool updateShouldNotify(TutorialScopeData oldWidget) =>
      oldWidget.token != token;
}

class TutorialScreenScope extends StatefulWidget {
  const TutorialScreenScope(
      {super.key,
      required this.screenId,
      required this.child,
      this.ready = true});
  final String screenId;
  final Widget child;
  final bool ready;
  @override
  State<TutorialScreenScope> createState() => _TutorialScreenScopeState();
}

class _TutorialScreenScopeState extends State<TutorialScreenScope> {
  final _token = Object();
  TutorialRuntime? _runtime;
  ModalRoute<dynamic>? _route;
  bool _visible = true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runtime = context.read<TutorialRuntime?>();
    _visible = TutorialVisibility.of(context);
    final route = ModalRoute.of(context);
    if (_route != route) {
      _route?.animation?.removeStatusListener(_transition);
      _route = route;
      _route?.animation?.addStatusListener(_transition);
    }
    _update();
  }

  void _transition(AnimationStatus _) => _runtime?.changed();
  void _update() => _runtime?.putScene(
      TutorialScene(_token, widget.screenId, _route, _visible && widget.ready));
  @override
  void didUpdateWidget(TutorialScreenScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_transition);
    _runtime?.removeScene(_token);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TutorialController?>();
    final guiding = controller?.guiding(widget.screenId) ?? false;
    return TutorialScopeData(
        token: _token,
        child: PopScope(
            canPop: !guiding,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop && guiding) controller?.showLeaveMenu();
            },
            child: widget.child));
  }
}
