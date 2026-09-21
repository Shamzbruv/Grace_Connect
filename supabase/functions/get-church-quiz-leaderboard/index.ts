import {
  accessTokenFromRequest, anonClient, authenticatedUser, handleOptions,
  jamaicaMonthLabel, jsonResponse,
  parseJamaicaMonthKey, profileDisplayName, profileQuizChurchId,
  profileQuizScope, serviceClient, userProfile,
} from '../_shared/grace.ts';

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== 'POST') return jsonResponse({ error: 'POST required.' }, 405);
  try {
    const user = await authenticatedUser(request);
    const client = serviceClient();
    const profile = await userProfile(client, user.id);
    const scope = profileQuizScope(profile);
    const churchId = profileQuizChurchId(profile);
    const body = await request.json().catch(() => ({}));
    // Aggregate in Postgres: fetching attempt rows here silently capped scores
    // at the Data API's row limit and could omit the viewer entirely.
    const { data: ranking, error: rankingError } = await anonClient(
      accessTokenFromRequest(request) ?? undefined,
    ).rpc('list_quiz_ranking', {
      p_scope: scope, p_quiz_month: body.quiz_month ?? null, result_limit: 50,
    });
    if (rankingError) throw rankingError;
    // The RPC validates the input and selects the current month using the
    // ranking's calendar (UTC globally, the existing church quiz calendar locally).
    const monthKey = `${ranking.month}-01`;
    const month = parseJamaicaMonthKey(monthKey);
    const entries = (ranking.entries ?? []).map((row: Record<string, unknown>) => ({
      rank: row.rank, member_id: row.user_id, display_name: row.user_name,
      photo_url: row.photo_url ?? '', total_points: row.total_score,
      correct_answers: row.correct_answers, perfect_quizzes: row.perfect_quizzes,
      quizzes_completed: row.quizzes_completed, is_current_user: row.is_viewer,
    }));
    // Saved church awards remain historical. Visitor awards are not worldwide awards.
    let winners: Record<string, unknown>[] = [];
    const monthKeys = new Set<string>([monthKey]);
    if (scope === 'church') {
      const { data: rows, error } = await client.from('monthly_quiz_winners')
        .select('id,member_id,rank,total_points,correct_answers,perfect_quizzes,quiz_month')
        .eq('church_id', churchId).eq('quiz_month', monthKey).order('rank').limit(3);
      if (error) throw error;
      for (const row of rows ?? []) {
        const { data: person, error: personError } = await client.from('users')
          .select('id,uid,fullName,displayName,photoUrl')
          .or(`id.eq.${row.member_id},uid.eq.${row.member_id}`).limit(1).maybeSingle();
        if (personError) throw personError;
        winners.push({ ...row, display_name: profileDisplayName(person ?? {}),
          photo_url: person?.photoUrl ?? '' });
      }
      const { data: months, error: monthsError } = await client.from('monthly_quiz_winners')
        .select('quiz_month').eq('church_id',churchId).order('quiz_month',{ascending:false}).limit(120);
      if (monthsError) throw monthsError;
      for (const row of months ?? []) monthKeys.add(row.quiz_month);
    }
    return jsonResponse({
      ok: true, quiz_month: monthKey, month_label: jamaicaMonthLabel(month),
      next_month_at: ranking.next_month_at,
      entries, current_member: ranking.viewer ? {
        rank: ranking.viewer.rank, total_points: ranking.viewer.total_score,
      } : null, winners,
      leaderboard_scope: scope,
      leaderboard_label: scope === 'global' ? 'Worldwide' : 'Church members',
      available_months: [...monthKeys].sort().reverse().map(key => ({
        quiz_month: key, label: jamaicaMonthLabel(parseJamaicaMonthKey(key)),
      })),
    });
  } catch (error) {
    return jsonResponse({error: error instanceof Error ? error.message : 'Unable to load leaderboard.'},400);
  }
});
