import {
  accessTokenFromRequest,
  anonClient,
  authenticatedUser,
  handleOptions,
  jsonResponse,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

type RequestBody = {
  membershipId?: string;
  event?: "request" | "approved";
};

function displayName(row: Record<string, unknown> | null | undefined): string {
  const name = String(row?.fullName ?? row?.displayName ?? "").trim();
  if (name) return name;
  const email = String(row?.email ?? "").trim();
  if (email.includes("@")) return email.split("@")[0];
  return "A member";
}

function churchDisplayName(row: Record<string, unknown> | null | undefined, fallback: string): string {
  return String(row?.display_name ?? row?.name ?? row?.placeId ?? fallback).trim() || fallback;
}

Deno.serve(async (request) => {
  const options = handleOptions(request);
  if (options) return options;

  if (request.method !== "POST") {
    return jsonResponse({ error: "POST required." }, 405);
  }

  try {
    const user = await authenticatedUser(request);
    const body = (await request.json().catch(() => ({}))) as RequestBody;
    const membershipId = String(body.membershipId ?? "").trim();
    const event = body.event === "approved" ? "approved" : "request";
    if (!membershipId) {
      return jsonResponse({ error: "membershipId is required." }, 400);
    }

    const client = serviceClient();
    const { data: membership, error: membershipError } = await client
      .from("church_memberships")
      .select("id,user_id,church_id,membership_status,reviewed_by")
      .eq("id", membershipId)
      .maybeSingle();

    if (membershipError || !membership) {
      return jsonResponse({ error: "Membership request not found." }, 404);
    }

    const churchId = String(membership.church_id ?? "").trim();
    if (event === "request") {
      if (String(membership.user_id) !== user.id) {
        return jsonResponse({ error: "You can only notify leaders about your own request." }, 403);
      }
      if (String(membership.membership_status) !== "pending") {
        return jsonResponse({ error: "Only pending membership requests can be pushed." }, 409);
      }
    } else {
      if (String(membership.membership_status) !== "active") {
        return jsonResponse({ error: "Only approved memberships can be pushed." }, 409);
      }
      const token = accessTokenFromRequest(request);
      const callerClient = anonClient(token ?? undefined);
      const { data: canManage } = await callerClient.rpc(
        "can_manage_church_members",
        { target_church_id: churchId },
      );
      const isReviewer = String(membership.reviewed_by ?? "") === user.id;
      if (!isReviewer && canManage !== true) {
        return jsonResponse({ error: "You cannot notify this member about approval." }, 403);
      }
    }

    const eventType = event === "approved"
      ? "membership_approved"
      : "membership_request_received";
    const { data: claimed, error: claimError } = await client.rpc(
      "claim_membership_push_delivery",
      {
        p_membership_id: membershipId,
        p_event_type: eventType,
      },
    );
    if (claimError) throw claimError;
    if (claimed !== true) {
      return jsonResponse({
        ok: true,
        sent: false,
        deduplicated: true,
        reason: "This membership notification was already sent or is in progress.",
      });
    }

    const { data: church } = await client
      .from("churches")
      .select("display_name,name,placeId")
      .or(`id.eq.${churchId},placeId.eq.${churchId}`)
      .maybeSingle();

    const { data: requester } = await client
      .from("users")
      .select("fullName,displayName,email")
      .or(`id.eq.${user.id},uid.eq.${user.id}`)
      .maybeSingle();

    const churchName = churchDisplayName(church, churchId || "your church");
    const requesterName = displayName(requester);
    const result = await sendTopicPush(client, {
      topic: event === "approved"
        ? `user_${String(membership.user_id)}`
        : `church_${churchId}_leaders`,
      title: event === "approved" ? "Membership approved" : "New membership request",
      body: event === "approved"
        ? `Your request to join ${churchName} was approved.`
        : `${requesterName} requested to join ${churchName}.`,
      route: event === "approved" ? "/dashboard" : "/membership_requests",
      type: eventType,
      entityTable: "church_memberships",
      entityId: membershipId,
    });

    await client
      .from("membership_push_deliveries")
      .update({
        status: result.sent ? "sent" : "failed",
        completed_at: new Date().toISOString(),
        error_message: result.sent ? null : (result.reason ?? "Push delivery failed."),
      })
      .eq("membership_id", membershipId)
      .eq("event_type", eventType);

    return jsonResponse({
      ok: result.sent,
      sent: result.sent,
      reason: result.reason ?? null,
    }, result.sent ? 200 : 202);
  } catch (error) {
    return jsonResponse({
      error: error instanceof Error ? error.message : "Unable to send membership request push.",
    }, 500);
  }
});
