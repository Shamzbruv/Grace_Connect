import {
  handleOptions,
  jamaicaDateString,
  jsonResponse,
  requireCronSecret,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

type GraceRoomRow = {
  id: string;
  title: string;
  live_participant_count?: number | null;
  sort_order?: number | null;
};

type InvitationClaim = {
  id?: string;
  room_id?: string;
  attempt_count?: number;
  should_create_in_app?: boolean;
  in_app_count?: number;
};

const invitationMessages = [
  "Someone may need a listening ear tonight—or you may need one yourself.",
  "Pause in a Grace Room to encourage someone or receive support yourself.",
  "Grace Rooms are open for anonymous, caring, faith-centered conversation.",
];

function invitationSlot(): string {
  return "evening-support";
}

function selectRoom(rooms: GraceRoomRow[], date: string): GraceRoomRow | null {
  if (rooms.length === 0) return null;

  const occupied = rooms
    .filter((room) => Number(room.live_participant_count ?? 0) > 0)
    .sort((left, right) =>
      Number(right.live_participant_count ?? 0) -
        Number(left.live_participant_count ?? 0) ||
      Number(left.sort_order ?? 0) - Number(right.sort_order ?? 0)
    );
  if (occupied.length > 0) return occupied[0];

  const dateSeed = Number(date.replaceAll("-", ""));
  return rooms[dateSeed % rooms.length];
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;
  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

  const forbidden = requireCronSecret(request, "DAILY_QUIZ_CRON_SECRET");
  if (forbidden) return forbidden;

  const client = serviceClient();
  const invitationDate = jamaicaDateString();
  const slot = invitationSlot();

  const { data: rooms, error: roomsError } = await client
    .from("grace_rooms")
    .select("id,title,live_participant_count,sort_order")
    .eq("is_platform_room", true)
    .eq("status", "open")
    .order("sort_order", { ascending: true });
  if (roomsError) return jsonResponse({ error: roomsError.message }, 500);

  const room = selectRoom((rooms ?? []) as GraceRoomRow[], invitationDate);
  if (!room) return jsonResponse({ ok: true, status: "no_open_rooms" });

  const { data: claimData, error: claimError } = await client.rpc(
    "claim_grace_room_invitation_run",
    {
      p_invitation_date: invitationDate,
      p_invitation_slot: slot,
      p_room_id: room.id,
    },
  );

  if (claimError) {
    return jsonResponse({ error: claimError?.message ?? "Unable to claim invitation." }, 500);
  }
  if (!claimData) {
    return jsonResponse({ ok: true, status: "already_sent_or_in_progress" });
  }

  const claim = claimData as InvitationClaim;
  const runId = String(claim.id ?? "").trim();
  const claimedRoomId = String(claim.room_id ?? room.id).trim();
  const claimedRoom = (rooms ?? []).find((candidate) =>
    String(candidate.id) === claimedRoomId
  ) as GraceRoomRow | undefined;
  const deliveryRoom = claimedRoom ?? room;
  if (!runId) {
    return jsonResponse({ error: "Invitation claim did not return a run id." }, 500);
  }

  const liveCount = Number(deliveryRoom.live_participant_count ?? 0);
  const variation = Number(invitationDate.replaceAll("-", "")) % invitationMessages.length;
  const presenceText = liveCount > 0
    ? `${liveCount} ${liveCount === 1 ? "person is" : "people are"} present in ${deliveryRoom.title}.`
    : invitationMessages[variation];
  const title = liveCount > 0
    ? `Join ${deliveryRoom.title}`
    : "A Grace Room is open for you";
  const body = liveCount > 0
    ? `${presenceText} Offer support or find a safe place to talk.`
    : `${presenceText} Visit ${deliveryRoom.title}.`;
  const route = `/grace_rooms/room?id=${encodeURIComponent(deliveryRoom.id)}`;

  let inAppCount = Number(claim.in_app_count ?? 0);
  if (claim.should_create_in_app !== false) {
    const { data: createdCount, error: inAppError } = await client.rpc(
      "create_grace_room_invitation_notifications",
      {
        p_run_id: runId,
        p_title: title,
        p_body: body,
        p_route: route,
      },
    );
    if (inAppError) {
      return jsonResponse({ error: inAppError.message }, 500);
    }
    inAppCount = Number(createdCount ?? 0);
  }
  const push = await sendTopicPush(client, {
    topic: "graceconnect_all",
    title,
    body,
    route,
    type: "grace_room_invitation",
    entityTable: "grace_room_invitation_runs",
    entityId: runId,
  });

  const { error: completionError } = await client
    .from("grace_room_invitation_runs")
    .update({
      in_app_count: inAppCount,
      push_sent: push.sent,
      provider_error: push.reason ?? null,
      completed_at: push.sent ? new Date().toISOString() : null,
    })
    .eq("id", runId);
  if (completionError) {
    return jsonResponse({ error: completionError.message }, 500);
  }

  return jsonResponse({
    ok: push.sent,
    room_id: deliveryRoom.id,
    attempt_count: Number(claim.attempt_count ?? 1),
    live_count: liveCount,
    in_app_count: inAppCount,
    push_sent: push.sent,
    push_error: push.reason ?? null,
  }, push.sent ? 200 : 502);
});
