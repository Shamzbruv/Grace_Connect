import 'package:flutter/material.dart';
import 'tutorial_controller.dart';

class TutorialTooltip extends StatelessWidget {
  const TutorialTooltip({super.key, required this.controller});
  final TutorialController controller;
  @override
  Widget build(BuildContext context) {
    final step = controller.step!;
    final theme = Theme.of(context);
    final last = controller.activeStepIndex == controller.steps.length - 1;
    final counter =
        '${controller.activeStepIndex + 1} of ${controller.steps.length}';
    return Semantics(
        container: true,
        liveRegion: true,
        scopesRoute: true,
        explicitChildNodes: true,
        label: 'Step $counter. ${step.title}. ${step.message}',
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 12,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Text(step.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700))),
                            IconButton(
                                key: const ValueKey('tutorial-close'),
                                onPressed: controller.showLeaveMenu,
                                icon: const Icon(Icons.close,
                                    semanticLabel: 'Leave this guide'),
                                visualDensity: VisualDensity.compact),
                          ]),
                      const SizedBox(height: 4),
                      Text(step.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  )),
            ),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                          label: 'Step $counter',
                          child: Text(counter,
                              style: theme.textTheme.labelMedium)),
                      const SizedBox(height: 8),
                      Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (controller.activeStepIndex > 0)
                              TextButton(
                                  onPressed: controller.previous,
                                  child: const Text('Back')),
                            FilledButton(
                                onPressed: controller.next,
                                child: Text(last ? 'Got it' : 'Next')),
                          ]),
                    ])),
          ]),
        ));
  }
}
