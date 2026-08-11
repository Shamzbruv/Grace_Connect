/**
 * Grace Connect Cloud Functions (Gen 2 ONLY)
 * Restored full feature set: Email, Prayer Tasks, Role Management.
 */

const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const fetch = require("node-fetch");
const functions = require("firebase-functions"); // For config() access only

// Lazy initialize Admin SDK to prevent deployment analyzer timeouts
const { onInit } = require("firebase-functions/v2/core");
let isInit = false;
function ensureInit() {
  if (!isInit) {
    admin.initializeApp();
    isInit = true;
  }
}
onInit(() => ensureInit());

const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");

// --- 1. UTILS ---

function getTransporter() {
  const gmailEmail = functions.config().gmail?.email;
  const gmailPassword = functions.config().gmail?.app_password;

  if (!gmailEmail || !gmailPassword) {
    console.warn("Missing Gmail credentials in functions config.");
    return null;
  }

  return nodemailer.createTransport({
    service: "gmail",
    auth: { user: gmailEmail, pass: gmailPassword },
  });
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function graceConnectEmailTemplate({ title, preview, bodyHtml, footer }) {
  const safeTitle = escapeHtml(title || "Grace Connect");
  const safePreview = escapeHtml(preview || title || "Grace Connect update");
  return `<!doctype html>
    <html>
      <body style="margin:0;padding:0;background:#f7f3ea;font-family:Arial,Helvetica,sans-serif;color:#263852;">
        <div data-grace-email="true" style="display:none;max-height:0;overflow:hidden;opacity:0;">${safePreview}</div>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f3ea;padding:32px 12px;">
          <tr><td align="center">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #eadcb6;box-shadow:0 14px 36px rgba(13,31,76,0.12);">
              <tr><td style="background:#0d1f4c;padding:28px 32px;color:#ffffff;">
                <div style="font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#e5bd53;">Grace Connect</div>
                <h1 style="margin:8px 0 0;font-size:28px;line-height:1.2;font-weight:800;">${safeTitle}</h1>
              </td></tr>
              <tr><td style="padding:30px 32px;font-size:16px;line-height:1.65;color:#263852;">${bodyHtml}</td></tr>
              <tr><td style="padding:20px 32px;background:#fbf8f0;border-top:1px solid #eadcb6;color:#69768b;font-size:13px;line-height:1.5;">
                ${escapeHtml(footer || "Sent securely by Grace Connect.")}
              </td></tr>
            </table>
          </td></tr>
        </table>
      </body>
    </html>`;
}

// --- 2. CORE FUNCTIONS ---

// Connectivity Check
exports.ping = onCall(async () => {
  return { ok: true, message: "Grace Connect functions running (v2)" };
});

function normalizeRole(role) {
  return String(role || "")
    .trim()
    .toLowerCase()
    .replace(/&/g, "and")
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

function normalizePrivilege(privilege) {
  return String(privilege || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

function normalizeNotificationType(type) {
  return String(type || "general")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "_");
}

const SUPABASE_URL = "https://nimgsgnkcvddomrgkawb.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN";
const APP_WIDE_TOPIC = "graceconnect_all";

const PUBLIC_BROADCAST_TYPES = new Set([
  "announcement",
  "live_stream",
  "general",
  "testimony",
]);

function hasAnyPrivilege(profile, allowedPrivileges) {
  const privileges = Array.isArray(profile.appPrivileges) ? profile.appPrivileges : [];
  return privileges.some((privilege) => allowedPrivileges.has(normalizePrivilege(privilege)));
}

function canSendChurchWidePush(profile, type) {
  if (type === "testimony") {
    return Boolean(profile.placeId);
  }

  const allowedRoles = new Set([
    "pastor",
    "senior_pastor",
    "assistant_pastor",
    "acting_pastor",
    "church_admin",
    "admin",
    "administrator",
    "secretary",
    "church_secretary",
  ]);

  const hasAllowedRole =
    Array.isArray(profile.roles) && profile.roles.some((role) => allowedRoles.has(normalizeRole(role)));
  if (hasAllowedRole) return true;

  const allowedPrivileges = new Set([
    "sendpushnotification",
    "createannouncement",
  ]);
  if (type === "live_stream") {
    allowedPrivileges.add("managelivestream");
  }
  return hasAnyPrivilege(profile, allowedPrivileges);
}

function notificationSoundProfile(type) {
  const normalized = normalizeNotificationType(type);
  const profiles = {
    general: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    announcement: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    community: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    like: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    comment: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
    message: { channelId: "grace_messages_channel_v1", sound: "grace_message.wav" },
    direct_message: { channelId: "grace_messages_channel_v1", sound: "grace_message.wav" },
    prayer: { channelId: "grace_prayer_channel_v1", sound: "grace_prayer.wav" },
    prayer_request: { channelId: "grace_prayer_channel_v1", sound: "grace_prayer.wav" },
    daily_motivation: { channelId: "grace_daily_word_channel_v1", sound: "grace_daily.wav" },
    daily_devotional: { channelId: "grace_daily_word_channel_v1", sound: "grace_daily.wav" },
    daily_bible_quiz: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    quiz: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    monthly_quiz_winners: { channelId: "grace_daily_quiz_channel_v1", sound: "grace_quiz.wav" },
    live_stream: { channelId: "grace_live_channel_v1", sound: "grace_live.wav" },
    testimony: { channelId: "grace_default_channel_v1", sound: "grace_default.wav" },
  };
  return profiles[normalized] || profiles.general;
}

function userTopicFor(userId) {
  return `user_${String(userId || "").trim()}`;
}

function defaultRouteForType(type) {
  if (type === "direct_message") return "/inbox";
  if (type === "live_stream") return "/live_streaming";
  return "/announcements";
}

function notificationTag({ type, route, entityTable, entityId }) {
  if (entityTable && entityId) return `entity:${entityTable}:${entityId}`;
  if (route) return `route:${route}`;
  return `type:${type || "general"}`;
}

function stringMap(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entryValue]) => entryValue !== undefined && entryValue !== null)
      .map(([key, entryValue]) => [String(key), String(entryValue)]),
  );
}

function normalizeStringArray(value) {
  if (Array.isArray(value)) return value.map((entry) => String(entry));
  if (typeof value === "string") {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((entry) => String(entry));
    } catch (_) {
      return value.split(",").map((entry) => entry.trim());
    }
  }
  return [];
}

async function canSendDirectMessagePush(supabaseToken, senderUid, payload) {
  const recipientUserId = String(payload.recipientUserId || "").trim();
  const conversationId = String(payload.conversationId || "").trim();
  if (!recipientUserId || !conversationId || recipientUserId === senderUid) return false;

  const conversationResponse = await fetch(
    `${SUPABASE_URL}/rest/v1/direct_conversations?id=eq.${encodeURIComponent(conversationId)}&select=id,member_ids`,
    {
      method: "GET",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${supabaseToken}`,
        "Accept": "application/json",
      },
    },
  );

  if (!conversationResponse.ok) return false;
  const conversations = await conversationResponse.json();
  const conversation = conversations && conversations[0];
  const memberIds = normalizeStringArray(conversation?.member_ids);
  return memberIds.includes(senderUid) && memberIds.includes(recipientUserId);
}

async function getSupabaseUserProfile(supabaseToken) {
  const userResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    method: "GET",
    headers: {
      "apikey": SUPABASE_ANON_KEY,
      "Authorization": `Bearer ${supabaseToken}`,
    },
  });

  if (!userResponse.ok) {
    throw new HttpsError("unauthenticated", "Invalid Supabase token.");
  }

  const userData = await userResponse.json();
  const uid = userData.id;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Supabase user ID missing.");
  }

  const profileResponse = await fetch(
    `${SUPABASE_URL}/rest/v1/users?uid=eq.${uid}`,
    {
      method: "GET",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${supabaseToken}`,
        "Accept": "application/json",
      },
    },
  );

  if (!profileResponse.ok) {
    throw new HttpsError("permission-denied", "Unable to verify user profile.");
  }

  const profiles = await profileResponse.json();
  const profile = profiles && profiles[0];
  if (!profile) {
    throw new HttpsError("not-found", "User profile not found.");
  }

  return { uid, profile };
}

exports.sendTopicNotification = onRequest({ cors: true }, async (request, response) => {
  ensureInit();

  if (request.method !== "POST") {
    response.status(405).json({ error: "POST required." });
    return;
  }

  try {
    const authHeader = request.get("Authorization") || "";
    const supabaseToken = authHeader.startsWith("Bearer ")
      ? authHeader.substring("Bearer ".length)
      : "";

    if (!supabaseToken) {
      response.status(401).json({ error: "Missing authorization token." });
      return;
    }

    const { uid, profile } = await getSupabaseUserProfile(supabaseToken);
    const { title, body, topic, route, type, data } = request.body || {};
    const normalizedType = normalizeNotificationType(type);
    const churchTopic = `church_${profile.placeId || ""}`;
    const extraData = stringMap(data);
    const cleanTopic = String(topic || "").trim();
    const isAppWideLiveTopic =
      normalizedType === "live_stream" && cleanTopic === APP_WIDE_TOPIC;
    const isChurchTopic = cleanTopic === churchTopic;
    const isDirectMessageTopic =
      normalizedType === "direct_message" &&
      cleanTopic === userTopicFor(extraData.recipientUserId);

    if (!title || !body || !cleanTopic) {
      response.status(400).json({ error: "Invalid notification payload." });
      return;
    }

    if (normalizedType === "direct_message") {
      if (!isDirectMessageTopic ||
          !(await canSendDirectMessagePush(supabaseToken, uid, extraData))) {
        response.status(403).json({ error: "User cannot send this direct message push." });
        return;
      }
    } else if (!PUBLIC_BROADCAST_TYPES.has(normalizedType)) {
      response.status(400).json({ error: "Only public church-wide broadcasts can use topic push." });
      return;
    } else if (!isChurchTopic && !isAppWideLiveTopic) {
      response.status(400).json({ error: "Notification topic is not allowed for this broadcast." });
      return;
    } else if (!canSendChurchWidePush(profile, normalizedType)) {
      response.status(403).json({ error: "User cannot send church-wide push notifications." });
      return;
    }

    const soundProfile = notificationSoundProfile(normalizedType);
    const cleanTitle = String(title).slice(0, 120);
    const cleanBody = String(body).slice(0, 220);
    const cleanRoute = String(route || defaultRouteForType(normalizedType));
    const cleanEntityTable = extraData.entityTable || extraData.entity_table || "";
    const cleanEntityId = extraData.entityId || extraData.entity_id || "";
    const tag = notificationTag({
      type: normalizedType,
      route: cleanRoute,
      entityTable: cleanEntityTable,
      entityId: cleanEntityId,
    });
    const messageId = await admin.messaging().send({
      topic: cleanTopic,
      notification: {
        title: cleanTitle,
        body: cleanBody,
      },
      android: {
        priority: "high",
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          channelId: soundProfile.channelId,
          color: "#0B5C7D",
          icon: "ic_stat_grace_connect",
          sound: soundProfile.sound.replace(".wav", ""),
          tag,
        },
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: soundProfile.sound,
          },
        },
      },
      data: {
        ...extraData,
        type: normalizedType,
        route: cleanRoute,
        entity_table: cleanEntityTable,
        entity_id: cleanEntityId,
        notification_tag: tag,
        title: cleanTitle,
        body: cleanBody,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    });

    response.json({ ok: true, messageId });
  } catch (error) {
    console.error("Topic notification failed:", error);
    const status = error instanceof HttpsError && error.code === "permission-denied" ? 403 : 500;
    response.status(status).json({ error: error.message || "Unable to send notification." });
  }
});

// Support Ticket Handler (Sends Email)
exports.onSupportTicketCreated = onDocumentCreated("support_tickets/{ticketId}", async (event) => {
  const snap = event.data;
  if (!snap) return;

  const ticket = snap.data();
  const ticketId = event.params.ticketId;

  // Idempotency check
  if (ticket.emailStatus === 'sent') return;

  const transporter = getTransporter();
  if (!transporter) {
    await snap.ref.update({ emailStatus: 'failed', emailError: 'Missing credentials' });
    return;
  }

  const subject = `[Grace Connect Support] ${ticket.issueType || 'Issue'} - ${ticketId}`;
  const htmlBody = graceConnectEmailTemplate({
    title: "New Support Request",
    preview: `${ticket.issueType || "Support"} report ${ticketId}`,
    bodyHtml: `
      <p style="margin-top:0;">A member submitted a Grace Connect support request.</p>
      <table role="presentation" width="100%" cellspacing="0" cellpadding="8" style="border-collapse:collapse;background:#fbf8f0;border:1px solid #eadcb6;border-radius:10px;">
        <tr><td style="font-weight:700;color:#0d1f4c;">Ticket</td><td>${escapeHtml(ticketId)}</td></tr>
        <tr><td style="font-weight:700;color:#0d1f4c;">Reporter</td><td>${escapeHtml(ticket.reporterEmail || "Not provided")}</td></tr>
        <tr><td style="font-weight:700;color:#0d1f4c;">Section</td><td>${escapeHtml(ticket.appSection || "General")}</td></tr>
        <tr><td style="font-weight:700;color:#0d1f4c;">Type</td><td>${escapeHtml(ticket.issueType || "Issue")}</td></tr>
      </table>
      <h2 style="margin:28px 0 10px;color:#0d1f4c;font-size:20px;">Member message</h2>
      <div style="white-space:pre-wrap;padding:16px;border-left:4px solid #c39213;background:#fffaf0;border-radius:6px;">${escapeHtml(ticket.description || "No description supplied.")}</div>
    `,
    footer: "Grace Connect support reports are private and should be handled with care.",
  });

  try {
    await transporter.sendMail({
      from: `"Grace Connect Support" <${functions.config().gmail.email}>`,
      to: "shamzbiz1@gmail.com",
      replyTo: ticket.reporterEmail || undefined,
      subject: subject,
      html: htmlBody,
    });

    await snap.ref.update({
      emailStatus: 'sent',
      emailedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  } catch (error) {
    console.error("Email send failed:", error);
    await snap.ref.update({ emailStatus: 'failed', emailError: error.toString() });
  }
});

// Prayer Task Assignment Notification
exports.onPrayerTaskCreated = onDocumentCreated("prayer_tasks/{taskId}", async (event) => {
  const task = event.data?.data();
  if (!task || !task.assignedToUid) return;

  const db = require("firebase-admin").firestore();
  // Get assigned user to find FCM tokens
  const userDoc = await db.collection("users").doc(task.assignedToUid).get();
  const tokens = userDoc.data()?.fcmTokens || [];

  if (tokens.length > 0) {
    await admin.messaging().sendToDevice(tokens, {
      notification: {
        title: "New Prayer Assignment",
        body: "You have been assigned a new prayer request.",
      },
      data: {
        taskId: event.params.taskId,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        screen: "prayer_tasks"
      }
    });
  }
});

// Prayer Task Status Updates
exports.onPrayerTaskUpdated = onDocumentUpdated("prayer_tasks/{taskId}", async (event) => {
  const newData = event.data.after.data();
  const oldData = event.data.before.data();

  if (newData && oldData && newData.status !== oldData.status) {
    console.log(`Prayer Task ${event.params.taskId} status changed: ${oldData.status} -> ${newData.status}`);
    // Future: Notify requester depending on status
  }
});

// Role Management (Secure Callable)
exports.manageRole = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Login required.');

  const { targetUid, action, role, churchId } = request.data;
  if (!targetUid || !action || !role || !churchId) throw new HttpsError('invalid-argument', 'Missing fields.');

  const db = require("firebase-admin").firestore();

  // Verify Requester Permissions
  const requesterSnap = await db.collection('users').doc(request.auth.uid).get();
  const churchSnap = await db.collection('churches').doc(churchId).get();

  if (!requesterSnap.exists || !churchSnap.exists) throw new HttpsError('not-found', 'User or Church not found.');

  const rData = requesterSnap.data();
  const cData = churchSnap.data();
  const isOwner = cData.ownerUserId === request.auth.uid;
  // Check if requester has high-level role in roles array
  const canManage = isOwner || (rData.roles && (rData.roles.includes('Pastor') || rData.roles.includes('Admin')));

  if (!canManage) throw new HttpsError('permission-denied', 'You do not have permission to manage roles.');

  // Apply Role Change
  const targetRef = db.collection('users').doc(targetUid);
  await targetRef.update({
    roles: action === 'add'
      ? admin.firestore.FieldValue.arrayUnion(role)
      : admin.firestore.FieldValue.arrayRemove(role)
  });

  return { success: true };
});

// Weekly Absence Check (Scheduled)
exports.weeklyAbsenceCheck = onSchedule("every sunday 23:00", async () => {
  console.log("Weekly absence check running...");
  // Stub for logic to check check-ins vs total members
});

// Role Synchronization to Auth Custom Claims
exports.syncUserRolesToClaims = onDocumentWritten("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const newData = event.data.after.exists ? event.data.after.data() : null;

  if (!newData) {
    // User was deleted, nothing to do.
    return;
  }

  const roles = newData.roles || [];
  const placeId = newData.placeId || "";

  try {
    await admin.auth().setCustomUserClaims(userId, {
      roles: roles,
      placeId: placeId
    });
    console.log(`Successfully synced custom claims for user ${userId}: roles=[${roles}], placeId=${placeId}`);
  } catch (error) {
    console.error(`Error syncing custom claims for user ${userId}:`, error);
  }
});

// --- 3. CUSTOM AUTH ---

// Generate Firebase Custom Token from Supabase JWT
exports.generateCustomToken = onCall(async (request) => {
  const supabaseToken = request.data.supabaseToken;
  if (!supabaseToken) {
    throw new HttpsError('invalid-argument', 'Missing Supabase token.');
  }

  try {
    // Verify token using Supabase User Endpoint
    const response = await fetch('https://nimgsgnkcvddomrgkawb.supabase.co/auth/v1/user', {
      method: 'GET',
      headers: {
        'apikey': 'sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN',
        'Authorization': `Bearer ${supabaseToken}`,
      },
    });

    if (!response.ok) {
      console.error('Supabase token verification failed', response.status);
      throw new HttpsError('unauthenticated', 'Invalid Supabase token.');
    }

    const userData = await response.json();
    const uid = userData.id;

    if (!uid) {
      throw new HttpsError('unauthenticated', 'User ID not found in Supabase response.');
    }

    // Attempt to extract placeId and roles from Supabase app_metadata or user_metadata
    // If not found in the token verification context, we will query Supabase directly for the user profile
    let placeId = '';
    let roles = [];

    try {
      const supabaseUrl = 'https://nimgsgnkcvddomrgkawb.supabase.co/rest/v1/users?uid=eq.' + uid;
      const profileResponse = await fetch(supabaseUrl, {
        method: 'GET',
        headers: {
          'apikey': 'sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN',
          'Authorization': `Bearer ${supabaseToken}`,
          'Accept': 'application/json'
        }
      });

      if (profileResponse.ok) {
        const profileData = await profileResponse.json();
        if (profileData && profileData.length > 0) {
          placeId = profileData[0].placeId || '';
          roles = profileData[0].roles || [];
        }
      }
    } catch (err) {
      console.error("Error fetching user profile for custom token claims:", err);
    }

    const claims = {
      placeId: placeId,
      roles: roles
    };

    // Create Firebase custom token for this exact UID WITH custom claims
    const customToken = await admin.auth().createCustomToken(uid, claims);
    return { token: customToken };
  } catch (error) {
    console.error('Error generating custom token:', error);
    throw new HttpsError('internal', 'Unable to mint custom token.');
  }
});
