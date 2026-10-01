/// Download only the current/next reel. A reel just left may retain its
/// controller briefly; callers expire [warmPreviousIndex] after eight seconds.
bool shouldInitializeReel(
    {required int index,
    required int current,
    required bool dataSaver,
    required bool isActive,
    int? warmPreviousIndex}) {
  if (!isActive) return false;
  return index == current ||
      (!dataSaver &&
          (index == current + 1 ||
              (index == warmPreviousIndex && index == current - 1)));
}
