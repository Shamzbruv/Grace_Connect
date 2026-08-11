import {
  authenticatedUser,
  handleOptions,
  jamaicaMonthDateKey,
  jamaicaMonthLabel,
  jamaicaMonthRange,
  jsonResponse,
  parseJamaicaMonthKey,
  profileDisplayName,
  profileQuizChurchId,
  profileQuizScope,
  serviceClient,
  userProfile,
} from "../_shared/grace.ts";

type Row = {
  member_id: string;
  total_score: number;
  correct_answers: number;
  total_response_time_ms: number;
};

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  try {
    const client = serviceClient();
    const user = await authenticatedUser(request);
    const body = await request.json().catch(() => ({}));
    const profile = await userProfile(client, user.id);
    const churchId = profileQuizChurchId(profile);
    const leaderboardScope = profileQuizScope(profile);

    const selectedMonth = parseJamaicaMonthKey(String(body.quiz_month ?? ""));
    const selectedMonthKey = jamaicaMonthDateKey(selectedMonth);
    const { start, end } = jamaicaMonthRange(selectedMonth);

    const { data: attempts } = await client
      .from("quiz_attempts")
      .select("member_id, total_score, correct_answers, total_response_time_ms, completed_at")
      .eq("church_id_at_attempt", churchId)
      .eq("status", "completed")
      .gte("completed_at", start.toISOString())
      .lt("completed_at", end.toISOString());

    const grouped = new Map<string, Row & { perfect_quizzes: number; quizzes_completed: number }>();
    for (const attempt of attempts ?? []) {
      const memberId = String(attempt.member_id);
      const current = grouped.get(memberId) ?? {
        member_id: memberId,
        total_score: 0,
        correct_answers: 0,
        total_response_time_ms: 0,
        perfect_quizzes: 0,
        quizzes_completed: 0,
      };
      current.total_score += Number(attempt.total_score ?? 0);
      current.correct_answers += Number(attempt.correct_answers ?? 0);
      current.total_response_time_ms += Number(attempt.total_response_time_ms ?? 0);
      current.perfect_quizzes += Number(attempt.total_score ?? 0) === 100 ? 1 : 0;
      current.quizzes_completed += 1;
      grouped.set(memberId, current);
    }

    const { data: winnerRows } = await client
      .from("monthly_quiz_winners")
      .select("id, member_id, rank, total_points, correct_answers, perfect_quizzes, total_response_time_ms, quiz_month")
      .eq("church_id", churchId)
      .eq("quiz_month", selectedMonthKey)
      .order("rank", { ascending: true });

    const { data: allWinnerMonths } = await client
      .from("monthly_quiz_winners")
      .select("quiz_month")
      .eq("church_id", churchId)
      .order("quiz_month", { ascending: false });

    const availableMonthKeys = new Set<string>([selectedMonthKey]);
    for (const winner of allWinnerMonths ?? []) {
      const month = String(winner.quiz_month ?? "");
      if (month) availableMonthKeys.add(month);
    }

    const memberIds = Array.from(
      new Set([
        ...Array.from(grouped.keys()),
        ...(winnerRows ?? []).map((winner) => String(winner.member_id ?? "")),
      ].filter(Boolean)),
    );
    const { data: users } = memberIds.length
      ? await client.from("users").select("id, uid, fullName, displayName, photoUrl").in("id", memberIds)
      : { data: [] };
    const userMap = new Map((users ?? []).map((row) => [String(row.id ?? row.uid), row]));

    const entries = Array.from(grouped.values())
      .sort((a, b) =>
        b.total_score - a.total_score ||
        b.perfect_quizzes - a.perfect_quizzes ||
        b.correct_answers - a.correct_answers ||
        a.total_response_time_ms - b.total_response_time_ms ||
        a.member_id.localeCompare(b.member_id)
      )
      .map((entry, index) => {
        const member = (userMap.get(entry.member_id) ?? {}) as Record<string, unknown>;
        return {
          rank: index + 1,
          member_id: entry.member_id,
          display_name: profileDisplayName(member),
          photo_url: String(member.photoUrl ?? ""),
          total_points: entry.total_score,
          correct_answers: entry.correct_answers,
          perfect_quizzes: entry.perfect_quizzes,
          quizzes_completed: entry.quizzes_completed,
          is_current_user: entry.member_id === user.id,
        };
      });

    const currentMember = entries.find((entry) => entry.member_id === user.id) ?? null;
    const winners = (winnerRows ?? []).map((winner) => {
      const member = (userMap.get(String(winner.member_id)) ?? {}) as Record<string, unknown>;
      return {
        id: winner.id,
        rank: winner.rank,
        quiz_month: winner.quiz_month,
        member_id: winner.member_id,
        display_name: profileDisplayName(member),
        photo_url: String(member.photoUrl ?? ""),
        total_points: winner.total_points,
        correct_answers: winner.correct_answers,
        perfect_quizzes: winner.perfect_quizzes,
        total_response_time_ms: winner.total_response_time_ms,
      };
    });

    return jsonResponse({
      ok: true,
      quiz_month: selectedMonthKey,
      month_label: jamaicaMonthLabel(selectedMonth),
      next_month_at: end.toISOString(),
      entries: entries.slice(0, 50),
      current_member: currentMember,
      winners,
      leaderboard_scope: leaderboardScope,
      leaderboard_label: leaderboardScope === "global"
        ? "Grace Connect visitors"
        : "Church members",
      available_months: Array.from(availableMonthKeys)
        .sort()
        .reverse()
        .map((month) => {
          const date = parseJamaicaMonthKey(month);
          return {
            quiz_month: month,
            label: jamaicaMonthLabel(date),
          };
        }),
    });
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unable to load leaderboard." }, 400);
  }
});
