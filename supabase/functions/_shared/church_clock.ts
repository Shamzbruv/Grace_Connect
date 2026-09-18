/** Wall-clock conversions for IANA zones. No fixed country/UTC offset. */
function wallEpoch(instant: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(instant);
  const value = (name: string) => Number(parts.find(p => p.type === name)?.value);
  return Date.UTC(value('year'), value('month') - 1, value('day'),
    value('hour'), value('minute'), value('second'));
}

export function churchDateInfo(timeZone: string, daysBack = 0, now = new Date()) {
  const wall = new Date(wallEpoch(now, timeZone));
  const day = new Date(Date.UTC(wall.getUTCFullYear(), wall.getUTCMonth(),
    wall.getUTCDate() - daysBack));
  const isoDate = day.toISOString().slice(0, 10);
  const next = new Date(day.getTime() + 86_400_000).toISOString().slice(0, 10);
  return { isoDate, dayOfWeek: day.getUTCDay() || 7, daysBack,
    startUtc: churchWallTimeToUtc(isoDate, 0, timeZone),
    endUtc: churchWallTimeToUtc(next, 0, timeZone) };
}

export function churchWallTimeToUtc(isoDate: string, seconds: number, timeZone: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(isoDate) || !Number.isFinite(seconds)) {
    throw new Error('Invalid church date/time');
  }
  const target = Date.parse(isoDate + 'T00:00:00Z') + seconds * 1000;
  if (!Number.isFinite(target)) throw new Error('Invalid church date');
  const offsets = new Set<number>();
  for (const hours of [-36, 0, 36]) {
    const sample = new Date(target + hours * 3_600_000);
    offsets.add(wallEpoch(sample, timeZone) - sample.getTime());
  }
  const candidates = [...offsets].map(offset => new Date(target - offset));
  const exact = candidates.filter(date => wallEpoch(date, timeZone) === target);
  // Like Postgres AT TIME ZONE: choose the later occurrence during a fall-back,
  // and advance a nonexistent spring-forward clock time through the gap.
  if (exact.length) return new Date(Math.max(...exact.map(date => date.getTime())));
  const after = candidates.filter(date => wallEpoch(date, timeZone) > target)
    .sort((a, b) => wallEpoch(a, timeZone) - wallEpoch(b, timeZone));
  if (after.length) return after[0];
  throw new Error('Church time could not be resolved');
}
