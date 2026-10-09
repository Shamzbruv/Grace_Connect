/// Short counters never round into a milestone before it has been reached.
String compactCount(int count) {
  final value = count < 0 ? 0 : count;
  const units = {1000000000000: 'T', 1000000000: 'B', 1000000: 'M', 1000: 'K'};
  for (final entry in units.entries) {
    if (value >= entry.key) {
      final tenths = value ~/ (entry.key ~/ 10);
      return '${tenths ~/ 10}${tenths % 10 == 0 ? '' : '.${tenths % 10}'}${entry.value}';
    }
  }
  return value.toString();
}
