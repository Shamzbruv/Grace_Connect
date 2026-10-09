// Keep one common calendar for the shared church/global question set. Devices
// display these absolute instants in their own local time zone.
export const QUIZ_CALENDAR_ZONE = "America/Jamaica";

export function quizDateForPlay(now = new Date()): string {
  // Jamaica is UTC-5 without DST. Moving the calendar boundary to 06:00
  // keeps the previous day's quiz selected throughout the overnight window.
  return new Date(now.getTime() - 11 * 3_600_000).toISOString().slice(0, 10);
}

export function quizClosesAt(dateKey: string): Date {
  const date = new Date(`${dateKey}T11:00:00.000Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(dateKey) ||
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== dateKey
  ) {
    throw new Error("Invalid quiz date.");
  }
  date.setUTCDate(date.getUTCDate() + 1);
  return date;
}

export function isQuizPlayable(
  quiz: { status: string; available_at: string; expires_at: string } | null,
  now = new Date(),
): boolean {
  return quiz !== null && quiz.status === "published" &&
    new Date(quiz.available_at).getTime() <= now.getTime() &&
    now.getTime() < new Date(quiz.expires_at).getTime();
}
