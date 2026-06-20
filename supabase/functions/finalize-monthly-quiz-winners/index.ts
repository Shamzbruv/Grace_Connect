import {
  createInAppNotifications,
  handleOptions,
  jamaicaMonthDateKey,
  jamaicaMonthLabel,
  jamaicaMonthRange,
  jsonResponse,
  previousJamaicaMonthStart,
  requireCronSecret,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") return jsonResponse({ error: "POST required." }, 405);

  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const targetMonth = previousJamaicaMonthStart();
  const monthKey = jamaicaMonthDateKey(targetMonth);
  const monthLabel = jamaicaMonthLabel(targetMonth);
  const { start, end } = jamaicaMonthRange(targetMonth);

  const { data: attempts } = await client
    .from("quiz_attempts")
    .select("church_id_at_attempt, member_id, total_score, correct_answers, total_response_time_ms")
    .eq("status", "completed")
    .gte("completed_at", start.toISOString())
    .lt("completed_at", end.toISOString());

  const byChurch = new Map<string, Map<string, {
    total_points: number;
    correct_answers: number;
    perfect_quizzes: number;
    total_response_time_ms: number;
  }>>();

  for (const attempt of attempts ?? []) {
    const churchId = String(attempt.church_id_at_attempt ?? "");
    const memberId = String(attempt.member_id ?? "");
    if (!churchId || !memberId) continue;
    if (!byChurch.has(churchId)) byChurch.set(churchId, new Map());
    const current = byChurch.get(churchId)!.get(memberId) ?? {
      total_points: 0,
      correct_answers: 0,
      perfect_quizzes: 0,
      total_response_time_ms: 0,
    };
    current.total_points += Number(attempt.total_score ?? 0);
    current.correct_answers += Number(attempt.correct_answers ?? 0);
    current.perfect_quizzes += Number(attempt.total_score ?? 0) === 100 ? 1 : 0;
    current.total_response_time_ms += Number(attempt.total_response_time_ms ?? 0);
    byChurch.get(churchId)!.set(memberId, current);
  }

  let snapshots = 0;
  for (const [churchId, members] of byChurch.entries()) {
    const existing = await client
      .from("monthly_quiz_winners")
      .select("id")
      .eq("church_id", churchId)
      .eq("quiz_month", monthKey)
      .limit(1);
    if ((existing.data ?? []).length > 0) continue;

    const winners = Array.from(members.entries())
      .sort((a, b) =>
        b[1].total_points - a[1].total_points ||
        b[1].perfect_quizzes - a[1].perfect_quizzes ||
        b[1].correct_answers - a[1].correct_answers ||
        a[1].total_response_time_ms - b[1].total_response_time_ms ||
        a[0].localeCompare(b[0])
      )
      .slice(0, 3);

    const savedWinnerIds: string[] = [];
    for (let index = 0; index < winners.length; index++) {
      const [memberId, score] = winners[index];
      const { data: saved } = await client.from("monthly_quiz_winners").insert({
        church_id: churchId,
        quiz_month: monthKey,
        member_id: memberId,
        rank: index + 1,
        total_points: score.total_points,
        correct_answers: score.correct_answers,
        perfect_quizzes: score.perfect_quizzes,
        total_response_time_ms: score.total_response_time_ms,
      }).select("id").single();
      if (saved?.id) savedWinnerIds.push(String(saved.id));
      snapshots++;

      const placement = index === 0 ? "1st" : index === 1 ? "2nd" : "3rd";
      await client.from("notifications").insert({
        user_id: memberId,
        actor_id: null,
        actor_name: "Grace Connect",
        type: "monthly_quiz_winners",
        title: "Congratulations!",
        body: `You finished ${placement} place in Grace Connect’s Monthly Bible Quiz for ${monthLabel}.`,
        place_id: churchId,
        entity_table: "monthly_quiz_winners",
        entity_id: saved?.id ?? null,
        route: `/daily_bible_quiz?month=${monthKey}`,
      });
    }

    if (savedWinnerIds.length > 0) {
      const title = "Monthly Bible Quiz Winners";
      const body = "This month’s Bible Quiz winners have been announced. Tap to see the top three.";
      const route = `/daily_bible_quiz?month=${monthKey}`;
      await createInAppNotifications(client, {
        churchId,
        title,
        body,
        type: "monthly_quiz_winners",
        route,
        entityTable: "monthly_quiz_winners",
        entityId: monthKey,
        preferenceColumn: "notifyDailyQuiz",
      });
      await sendTopicPush(client, {
        topic: `church_${churchId}_quiz`,
        title,
        body,
        route,
        type: "daily_bible_quiz",
        entityTable: "monthly_quiz_winners",
        entityId: monthKey,
      });
    }
  }

  return jsonResponse({
    ok: true,
    quiz_month: monthKey,
    month_label: monthLabel,
    snapshots,
  });
});
