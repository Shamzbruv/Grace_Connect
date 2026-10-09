class TutorialStep {
  const TutorialStep(this.targetId, this.title, this.message);
  final String targetId, title, message;
  // Targets are explanatory only: progressing never activates the real control.
}
