import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tutorial_controller.dart';
import 'tutorial_overlay.dart';
import 'tutorial_registry.dart';
import 'tutorial_runtime.dart';

class TutorialHost extends StatefulWidget {
  const TutorialHost({super.key, required this.child});
  final Widget child;
  @override
  State<TutorialHost> createState() => _TutorialHostState();
}

class _TutorialHostState extends State<TutorialHost>
    with WidgetsBindingObserver {
  TutorialController? _controller;
  TutorialRuntime? _runtime;
  Timer? _settle;
  int _request = 0;
  bool _foreground = true,
      _positioning = false,
      _internal = false,
      _wasEditing = false;
  Object? _scene;
  String? _screenId;
  Rect? _rect;
  String? _positionedStep;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<TutorialController?>();
    final runtime = context.read<TutorialRuntime?>();
    if (_controller != controller || _runtime != runtime) {
      _controller?.removeListener(_controllerChanged);
      _runtime?.removeListener(_changed);
      _controller = controller;
      _runtime = runtime;
      controller?.addListener(_controllerChanged);
      runtime?.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _changed();
      }
    });
  }

  bool get _editing {
    final focus = FocusManager.instance.primaryFocus?.context;
    return focus?.widget is EditableText ||
        focus?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _focusChanged() {
    final editing = _editing;
    if (editing != _wasEditing) {
      _wasEditing = editing;
      _changed();
    }
  }

  bool get _blocked =>
      !_foreground ||
      _editing ||
      MediaQuery.viewInsetsOf(context).bottom > 0 ||
      _controller?.temporarilySuppressed == true ||
      _controller?.enabled != true ||
      _controller?.initialized != true;
  void _block(bool blocked) {
    _internal = true;
    _controller?.setHostBlocked(blocked);
    _internal = false;
  }

  void _controllerChanged() {
    if (!mounted || _internal) {
      return;
    }
    final controller = _controller!;
    if (controller.current != null &&
        _scene == _runtime?.active?.token &&
        !_blocked &&
        _positionedStep != controller.step?.targetId) {
      unawaited(_position(++_request));
    } else if (controller.current != null &&
        !_blocked &&
        _rect != null &&
        _runtime?.active?.token == _scene) {
      setState(() {});
    } else {
      _changed();
    }
  }

  void _changed() {
    if (!mounted) {
      return;
    }
    _request++;
    _settle?.cancel();
    final scene = _runtime?.active;
    _block(true);
    if (scene?.token != _scene || scene?.screenId != _screenId) {
      _scene = scene?.token;
      _screenId = scene?.screenId;
      _rect = null;
      _positionedStep = null;
      _internal = true;
      _controller?.screenChanged(scene?.screenId);
      _internal = false;
    }
    setState(() {});
    if (_blocked || scene == null) {
      return;
    }
    final request = _request;
    _settle = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || request != _request || _blocked) {
        return;
      }
      final definition = TutorialRegistry.definitions[scene.screenId];
      final controller = _controller!;
      if (definition == null ||
          controller.isSeen(definition.screenId, definition.version)) {
        return;
      }
      if (controller.current?.screenId != definition.screenId) {
        final available = definition.steps
            .where((s) => _runtime!.target(scene.token, s.targetId) != null)
            .toList();
        _internal = true;
        controller.start(definition, available);
        _internal = false;
      }
      await _position(request);
    });
  }

  Future<void> _position(int request) async {
    final scene = _runtime?.active, step = _controller?.step;
    if (scene == null || step == null || _blocked) {
      return;
    }
    final target = _runtime!.target(scene.token, step.targetId);
    if (target == null) {
      _controller!.removeMissingTarget(step.targetId);
      return;
    }
    _positioning = true;
    try {
      final motion = MediaQuery.disableAnimationsOf(context);
      // Reveal vertically scrolled controls without moving the horizontal
      // PageView that owns the app's selected navigation tab.
      final scrollable = Scrollable.maybeOf(target);
      final targetRender = target.findRenderObject();
      if (scrollable != null &&
          targetRender != null &&
          axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical) {
        await scrollable.position.ensureVisible(targetRender,
            duration:
                motion ? Duration.zero : const Duration(milliseconds: 280),
            alignment: .4,
            curve: Curves.easeOutCubic);
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          request != _request ||
          !target.mounted ||
          _blocked ||
          _runtime?.active?.token != scene.token) {
        return;
      }
      final render = target.findRenderObject(),
          host = context.findRenderObject();
      if (render is! RenderBox ||
          host is! RenderBox ||
          !render.attached ||
          !render.hasSize ||
          render.size.isEmpty) {
        _controller!.removeMissingTarget(step.targetId);
        return;
      }
      final rect =
          (host.globalToLocal(render.localToGlobal(Offset.zero)) & render.size)
              .intersect(Offset.zero & host.size);
      if (rect.isEmpty) {
        _controller!.removeMissingTarget(step.targetId);
        return;
      }
      _rect = rect;
      _positionedStep = step.targetId;
      _block(false);
      setState(() {});
    } catch (_) {
      if (mounted && request == _request) {
        _controller?.removeMissingTarget(step.targetId);
      }
    } finally {
      _positioning = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_controller?.synchronize());
    _changed();
  }

  @override
  void didChangeMetrics() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _changed();
        }
      });
  @override
  void dispose() {
    _request++;
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    _controller?.removeListener(_controllerChanged);
    _runtime?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _controller?.overlayVisible == true && _rect != null;
    return NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          if (!_positioning) {
            _runtime?.changed();
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
            onNotification: (_) {
              if (!_positioning && _controller?.current != null) {
                _runtime?.changed();
              }
              return false;
            },
            child: Stack(fit: StackFit.expand, children: [
              ExcludeSemantics(excluding: visible, child: widget.child),
              if (visible)
                Positioned.fill(
                    child: TutorialOverlay(
                        controller: _controller!, target: _rect!)),
            ])));
  }
}
