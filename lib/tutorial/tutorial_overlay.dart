import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tutorial_controller.dart';
import 'tutorial_tooltip.dart';

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay(
      {super.key, required this.controller, required this.target});
  final TutorialController controller;
  final Rect target;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              controller.showLeaveMenu(),
        },
        child: Focus(
            autofocus: true,
            child: LayoutBuilder(builder: (context, constraints) {
              final screen = Offset.zero & constraints.biggest;
              final safe = Rect.fromLTRB(
                  media.padding.left + 12,
                  media.padding.top + 12,
                  screen.right - media.padding.right - 12,
                  screen.bottom -
                      media.padding.bottom -
                      media.viewInsets.bottom -
                      12);
              final cutout = target.inflate(8).intersect(screen);
              final below = safe.bottom - cutout.bottom - 12;
              final above = cutout.top - safe.top - 12;
              final useBelow = below >= above;
              final room = math.max(below, above);
              final fallback = room < 150;
              final width = math.min(340.0, safe.width);
              final left = (target.center.dx - width / 2)
                  .clamp(safe.left, safe.right - width);
              final height =
                  fallback ? safe.height * .58 : math.min(room, safe.height);
              final reducedMotion = media.disableAnimations;
              return Stack(children: [
                // The cutout is visual, never a hole in pointer protection.
                const Positioned.fill(
                    child: ModalBarrier(
                        dismissible: false, color: Colors.transparent)),
                Positioned.fill(
                    child: IgnorePointer(
                        child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(begin: cutout, end: cutout),
                  duration: reducedMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (_, rect, child) =>
                      CustomPaint(painter: _SpotlightPainter(rect ?? cutout)),
                ))),
                if (!controller.leaveMenuVisible)
                  Positioned(
                      left: left,
                      width: width,
                      top: !fallback && useBelow ? cutout.bottom + 12 : null,
                      bottom: fallback
                          ? screen.bottom - safe.bottom
                          : useBelow
                              ? null
                              : screen.bottom - cutout.top + 12,
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: math.max(100, height)),
                          child: TutorialTooltip(
                              key: ValueKey(controller.step!.targetId),
                              controller: controller))),
                if (controller.leaveMenuVisible)
                  Positioned(
                      left: safe.left,
                      right: screen.right - safe.right,
                      bottom: screen.bottom - safe.bottom,
                      child: ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: safe.height),
                          child: Material(
                            color: Theme.of(context).colorScheme.surface,
                            elevation: 16,
                            borderRadius: BorderRadius.circular(20),
                            clipBehavior: Clip.antiAlias,
                            child: SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Semantics(
                                          liveRegion: true,
                                          header: true,
                                          child: Text('Leave this guide?',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge)),
                                      const SizedBox(height: 12),
                                      ListTile(
                                          leading: const Icon(
                                              Icons.skip_next_outlined),
                                          title: const Text('Skip this screen'),
                                          onTap: controller.skipCurrentScreen),
                                      ListTile(
                                          leading:
                                              const Icon(Icons.school_outlined),
                                          title:
                                              const Text('Turn off tutorials'),
                                          onTap: controller.disableTutorials),
                                      const SizedBox(height: 8),
                                      FilledButton(
                                          onPressed: () =>
                                              controller.showLeaveMenu(false),
                                          child: const Text('Continue guide')),
                                    ])),
                          ))),
              ]);
            })));
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.rect);
  final Rect rect;
  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(rect, const Radius.circular(16));
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(
        path, Paint()..color = const Color(0xFF10141C).withValues(alpha: .50));
    canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xFFFFBF00).withValues(alpha: .20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        hole,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFD2982C));
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}
