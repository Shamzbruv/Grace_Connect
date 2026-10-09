import 'tutorial_step.dart';

class TutorialDefinition {
  const TutorialDefinition(this.screenId, this.steps, {this.version = 1});
  final String screenId;
  final int version;
  final List<TutorialStep> steps;
}
