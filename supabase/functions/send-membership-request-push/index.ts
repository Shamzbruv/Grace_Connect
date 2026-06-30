import {
  authenticatedUser,
  handleOptions,
  jsonResponse,
  sendTopicPush,
  serviceClient,
} from "../_shared/grace.ts";

type RequestBody = {
  membershipId?: string;
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
    if (!membershipId) {
      return jsonResponse({ error: "membershipId is required." }, 400);
    }

    const client = serviceClient();
    const { data: membership, error: membershipError } = await client
      .from("church_memberships")
      .select("id,user_id,church_id,membership_status")
      .eq("id", membershipId)
      .maybeSingle();

    if (membershipError || !membership) {
      return jsonResponse({ error: "Membership request not found." }, 404);
    }

    if (String(membership.user_id) !== user.id) {
      return jsonResponse({ error: "You can only notify leaders about your own request." }, 403);
    }

    if (String(membership.membership_status) !== "pending") {
      return jsonResponse({ error: "Only pending membership requests can be pushed." }, 409);
    }

    const churchId = String(membership.church_id ?? "").trim();
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
      topic: `church_${churchId}_leaders`,
      title: "New membership request",
      body: `${requesterName} requested to join ${churchName}.`,
      route: "/membership_requests",
      type: "membership_request_received",
      entityTable: "church_memberships",
      entityId: membershipId,
    });

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
