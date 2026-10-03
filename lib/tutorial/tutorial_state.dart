/// Account-scoped, versioned progress. Older generations remain in the cache.
class TutorialProgress {
  const TutorialProgress(
      {required this.screenId,
      required this.generation,
      this.version = 1,
      this.status = 'completed',
      this.stepReached = 0});
  final String screenId;
  final int generation, version, stepReached;
  final String status;
  String get key => '$generation:$screenId:$version';
  Map<String, dynamic> toJson() => {
        'screen_id': screenId,
        'generation': generation,
        'tutorial_version': version,
        'status': status,
        'step_reached': stepReached
      };
  factory TutorialProgress.fromJson(Map<String, dynamic> map) =>
      TutorialProgress(
          screenId: map['screen_id'] as String,
          generation: map['generation'] as int,
          version: map['tutorial_version'] as int? ?? 1,
          status: map['status'] as String? ?? 'completed',
          stepReached: map['step_reached'] as int? ?? 0);
}

class TutorialState {
  TutorialState(
      {this.enabled = false,
      this.generation = 1,
      this.settingsDirty = false,
      this.progressDirty = false,
      Map<String, TutorialProgress>? progress})
      : progress = progress ?? {};
  final bool enabled, settingsDirty, progressDirty;
  final int generation;
  final Map<String, TutorialProgress> progress;
  bool get dirty => settingsDirty || progressDirty;
  bool hasSeen(String screen, int version) =>
      progress.containsKey('$generation:$screen:$version');
  TutorialState copyWith(
          {bool? enabled,
          int? generation,
          bool? settingsDirty,
          bool? progressDirty,
          Map<String, TutorialProgress>? progress}) =>
      TutorialState(
          enabled: enabled ?? this.enabled,
          generation: generation ?? this.generation,
          settingsDirty: settingsDirty ?? this.settingsDirty,
          progressDirty: progressDirty ?? this.progressDirty,
          progress: progress ?? Map.of(this.progress));
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'generation': generation,
        'settings_dirty': settingsDirty,
        'progress_dirty': progressDirty,
        'progress': progress.values.map((item) => item.toJson()).toList()
      };
  factory TutorialState.fromJson(Map<String, dynamic> map) {
    final items = (map['progress'] as List? ?? [])
        .map((e) => TutorialProgress.fromJson(Map<String, dynamic>.from(e)));
    return TutorialState(
        enabled: map['enabled'] == true,
        generation: (map['generation'] as int? ?? 1).clamp(1, 2147483646),
        settingsDirty: map['settings_dirty'] == true,
        progressDirty: map['progress_dirty'] == true,
        progress: {for (final item in items) item.key: item});
  }

  /// A restart wins over old history. Within a generation, learning is a union;
  /// a stale fetch can never make a locally completed screen new again.
  TutorialState merge(TutorialState remote, {bool acknowledged = false}) {
    final merged = Map<String, TutorialProgress>.of(remote.progress);
    for (final item in progress.values) {
      if (merged[item.key]?.status != 'completed') merged[item.key] = item;
    }
    final remoteWins = remote.generation > generation;
    return TutorialState(
        generation: remoteWins ? remote.generation : generation,
        enabled: remoteWins
            ? remote.enabled
            : generation > remote.generation
                ? enabled
                : settingsDirty && !acknowledged
                    ? enabled
                    : remote.enabled,
        settingsDirty: !acknowledged && !remoteWins && settingsDirty,
        progressDirty: !acknowledged && progressDirty,
        progress: merged);
  }
}
