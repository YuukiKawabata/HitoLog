import { randomBytes, createHash } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { DocumentData, FieldValue, getFirestore, QueryDocumentSnapshot, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getMessaging } from "firebase-admin/messaging";
import { getRemoteConfig } from "firebase-admin/remote-config";
import { logger } from "firebase-functions";
import { onCall, HttpsError, onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

if (getApps().length === 0) initializeApp();
const db = getFirestore();
const callableOptions = { region: "asia-northeast1", enforceAppCheck: true } as const;
const MAX_MEMBERS = 5;
const MAX_OWNED = 5;
const MAX_JOINED = 20;
const MAX_ACTIVE_INVITES = 5;
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const OPERATION_REQUEST_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const REACTIONS = new Set(["empathy", "insight", "cheer"]);
const PROMPTS_JA = [
  "今日、心に残ったことは？", "いま、誰かに伝えたいことは？", "今日の自分を一言で残すなら？",
  "小さくても、うれしかったことは？", "今日、考えが変わったことは？", "いま手放したい気持ちは？",
  "明日の自分に残したい言葉は？"
];
const PROMPTS_EN = [
  "What stayed with you today?", "What would you like to tell someone?", "Describe today in one line.",
  "What small thing made you happy?", "What changed your mind today?", "What feeling can you let go?",
  "What would you leave for tomorrow's you?"
];
let circlePushCache = { enabled: false, expiresAt: 0 };

function fail(code: string, message: string, firebaseCode: "invalid-argument" | "failed-precondition" | "permission-denied" | "already-exists" | "not-found" | "resource-exhausted" = "failed-precondition"): never {
  throw new HttpsError(firebaseCode, message, { code });
}

function uid(request: { auth?: { uid: string } }): string {
  if (!request.auth?.uid) fail("unauthenticated", "Sign in is required.", "permission-denied");
  return request.auth!.uid;
}

async function requireActiveUser(userID: string) {
  const user = await db.collection("users").doc(userID).get();
  if (!user.exists || user.data()?.isDeleted === true || user.data()?.isSuspended === true) {
    fail("permission-denied", "The account is not active.", "permission-denied");
  }
  return user;
}

async function requireAdmin(userID: string) {
  const user = await requireActiveUser(userID);
  if (user.data()?.isAdmin !== true) fail("permission-denied", "Admin permission is required.", "permission-denied");
  return user;
}

async function enforceRateLimit(subject: string, action: string, limit: number, windowMs: number) {
  const id = createHash("sha256").update(`${subject}:${action}`).digest("hex");
  const ref = db.collection("circleRateLimits").doc(id);
  await db.runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    const now = Date.now();
    const start = snapshot.data()?.windowStartedAt instanceof Timestamp ? snapshot.data()!.windowStartedAt.toMillis() : 0;
    const count = Number(snapshot.data()?.count ?? 0);
    if (!snapshot.exists || now - start >= windowMs) {
      transaction.set(ref, { action, count: 1, windowStartedAt: Timestamp.fromMillis(now), expiresAt: Timestamp.fromMillis(now + windowMs * 2) });
      return;
    }
    if (count >= limit) fail("rate-limited", "Too many requests. Please try again later.", "resource-exhausted");
    transaction.update(ref, { count: FieldValue.increment(1), expiresAt: Timestamp.fromMillis(start + windowMs * 2) });
  });
}

async function requireMember(circleID: string, userID: string, ownerOnly = false) {
  await enforceRateLimit(userID, "member-call", 120, 60_000);
  const [circle, member] = await Promise.all([
    db.collection("circles").doc(circleID).get(),
    db.collection("circles").doc(circleID).collection("members").doc(userID).get()
  ]);
  if (!circle.exists || circle.data()?.status !== "active" || !member.exists || member.data()?.status !== "active") {
    fail("permission-denied", "You are not an active member.", "permission-denied");
  }
  if (ownerOnly && member.data()?.role !== "owner") fail("permission-denied", "Owner permission is required.", "permission-denied");
  return { circle, member };
}

function input(request: { data?: unknown }): Record<string, unknown> {
  if (!request.data || typeof request.data !== "object" || Array.isArray(request.data)) fail("invalid-argument", "Invalid request.", "invalid-argument");
  return request.data as Record<string, unknown>;
}

function stringValue(data: Record<string, unknown>, key: string, max: number, allowEmpty = false): string {
  if (typeof data[key] !== "string") fail("invalid-argument", `${key} is required.`, "invalid-argument");
  const value = (data[key] as string).trim();
  if ((!allowEmpty && value.length === 0) || value.length > max) fail("invalid-argument", `${key} is invalid.`, "invalid-argument");
  return value;
}

function circleDTO(id: string, value: DocumentData) {
  const ms = (timestamp: unknown) => timestamp instanceof Timestamp ? timestamp.toMillis() : Date.now();
  return { id, name: value.name, emoji: value.emoji ?? "", ownerID: value.ownerID, memberCount: value.memberCount ?? 1,
    maxMembers: value.maxMembers ?? MAX_MEMBERS, status: value.status ?? "active", createdAt: ms(value.createdAt), updatedAt: ms(value.updatedAt) };
}

function tokenHash(token: string) { return createHash("sha256").update(token).digest("hex"); }
function operationRequestRef(userID: string, type: string, requestID: string) {
  const id = createHash("sha256").update(`${userID}:${type}:${requestID}`).digest("hex");
  return db.collection("circleOperationRequests").doc(id);
}
function operationRequest(type: string, userID: string, data: Record<string, unknown>) {
  return {
    type,
    userID,
    ...data,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + OPERATION_REQUEST_TTL_MS)
  };
}
function cleanupJobRef(type: string, circleID: string, subjectID = "circle") {
  const id = createHash("sha256").update(`${type}:${circleID}:${subjectID}`).digest("hex");
  return db.collection("circleOperationJobs").doc(id);
}
function cleanupJob(type: string, circleID: string, extra: Record<string, unknown> = {}) {
  return { type, circleID, ...extra, status: "pending", attempts: 0, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() };
}
function validToken(value: unknown): value is string { return typeof value === "string" && /^[A-Za-z0-9_-]{40,80}$/.test(value); }
function graphemes(value: string) { return [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(value)].length; }

function dateKey(date: Date, timeZone: string): string {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date);
    const get = (type: string) => parts.find(p => p.type === type)?.value;
    return `${get("year")}-${get("month")}-${get("day")}`;
  } catch { fail("invalid-timezone", "The timezone is invalid.", "invalid-argument"); }
}

function promptFor(key: string, locale: string) {
  const day = Math.floor(Date.parse(`${key}T00:00:00Z`) / 86_400_000);
  const prompts = locale.startsWith("en") ? PROMPTS_EN : PROMPTS_JA;
  const text = prompts[Math.abs(day) % prompts.length];
  return { id: `daily-${key}-${locale.startsWith("en") ? "en" : "ja"}`, text };
}

function jpegDimensions(buffer: Buffer) {
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) fail("invalid-media", "The image must be JPEG.", "invalid-argument");
  let offset = 2;
  while (offset + 4 < buffer.length) {
    if (buffer[offset] !== 0xff) { offset += 1; continue; }
    const marker = buffer[offset + 1];
    if (marker === 0xe1) fail("invalid-media", "Image metadata is not allowed.", "invalid-argument");
    if (marker === 0xd9 || marker === 0xda) break;
    const length = buffer.readUInt16BE(offset + 2);
    if (length < 2 || offset + 2 + length > buffer.length) break;
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      return { height: buffer.readUInt16BE(offset + 5), width: buffer.readUInt16BE(offset + 7) };
    }
    offset += 2 + length;
  }
  fail("invalid-media", "The JPEG dimensions could not be read.", "invalid-argument");
}

async function validateMedia(value: unknown, circleID: string, userID: string) {
  if (!Array.isArray(value) || value.length > 1) fail("invalid-argument", "Only one image is allowed.", "invalid-argument");
  return Promise.all(value.map(async item => {
    if (!item || typeof item !== "object") fail("invalid-argument", "Invalid media.", "invalid-argument");
    const media = item as Record<string, unknown>;
    const path = stringValue(media, "storagePath", 500);
    if (media.type !== "image" || !path.startsWith(`circleMedia/${circleID}/drafts/${userID}/`)) fail("permission-denied", "Invalid media path.", "permission-denied");
    const file = getStorage().bucket().file(path);
    let metadata;
    let imageBuffer;
    try {
      [metadata] = await file.getMetadata();
      [imageBuffer] = await file.download();
    } catch {
      fail("invalid-media", "The uploaded image was not found.", "invalid-argument");
    }
    const size = Number(metadata.size ?? imageBuffer.length);
    if (!Number.isFinite(size) || size <= 0 || size > 10 * 1024 * 1024) fail("media-too-large", "The image is too large.", "invalid-argument");
    if (metadata.contentType !== "image/jpeg") fail("invalid-media", "The image must be JPEG.", "invalid-argument");
    const dimensions = jpegDimensions(imageBuffer);
    if (dimensions.width <= 0 || dimensions.height <= 0 || dimensions.width > 1600 || dimensions.height > 1600) fail("invalid-media", "The image dimensions are invalid.", "invalid-argument");
    return { id: stringValue(media, "id", 100), type: "image", storagePath: path, width: dimensions.width, height: dimensions.height, durationMs: null, sizeBytes: size };
  }));
}

function metrics(value: unknown, bodyLength: number) {
  const data = value && typeof value === "object" ? value as Record<string, unknown> : {};
  const bounded = (key: string, max: number) => Math.min(Math.max(Number(data[key] ?? 0), 0), max);
  return { inputDurationMs: bounded("inputDurationMs", 86_400_000), characterCount: bodyLength,
    editCount: bounded("editCount", 100_000), deleteCount: bounded("deleteCount", 100_000),
    suspiciousBulkInputCount: bounded("suspiciousBulkInputCount", 100) };
}

function humanScore(value: ReturnType<typeof metrics>, aiAssisted: boolean, accountAgeDays: number) {
  let score = 100;
  if (value.suspiciousBulkInputCount > 0 && !aiAssisted) score -= 30 * value.suspiciousBulkInputCount;
  if (value.characterCount >= 100 && value.characterCount / Math.max(value.inputDurationMs / 1000, 1) > 10) score -= 20;
  if (accountAgeDays < 1) score -= 5;
  if (value.editCount > 0 || value.deleteCount > 0) score += 5;
  score = Math.min(Math.max(score, 0), 100);
  return { score, badge: score >= 80 ? "verified" : score >= 50 ? "checking" : "lowTrust" };
}

export const createCircle = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); await requireActiveUser(userID);
  await enforceRateLimit(userID, "create-circle", 10, 24 * 60 * 60 * 1000);
  const name = stringValue(data, "name", 30); const emoji = typeof data.emoji === "string" ? data.emoji.trim() : "";
  if (graphemes(emoji) > 1) fail("invalid-argument", "emoji is invalid.", "invalid-argument");
  const requestID = stringValue(data, "clientRequestID", 100);
  const requestRef = operationRequestRef(userID, "createCircle", requestID);
  const circleRef = db.collection("circles").doc();
  return db.runTransaction(async transaction => {
    const previous = await transaction.get(requestRef);
    if (previous.exists) {
      const existingID = previous.data()?.circleID as string; const existing = await transaction.get(db.collection("circles").doc(existingID));
      if (existing.exists) return { circle: circleDTO(existing.id, existing.data()!) };
    }
    const owned = await transaction.get(db.collection("users").doc(userID).collection("circleMemberships").where("role", "==", "owner").where("status", "==", "active"));
    if (owned.size >= MAX_OWNED) fail("circle-limit", "You have reached the owned-circle limit.", "resource-exhausted");
    const now = FieldValue.serverTimestamp();
    transaction.create(circleRef, { name, emoji, ownerID: userID, memberCount: 1, maxMembers: MAX_MEMBERS, status: "active", schemaVersion: 1, createdAt: now, updatedAt: now });
    transaction.create(circleRef.collection("members").doc(userID), { userID, role: "owner", status: "active", joinedAt: now, updatedAt: now });
    transaction.set(db.collection("users").doc(userID).collection("circleMemberships").doc(circleRef.id), { circleID: circleRef.id, role: "owner", status: "active", joinedAt: now, updatedAt: now });
    transaction.create(requestRef, operationRequest("createCircle", userID, { circleID: circleRef.id }));
    return { circle: { id: circleRef.id, name, emoji, ownerID: userID, memberCount: 1, maxMembers: MAX_MEMBERS, status: "active", createdAt: Date.now(), updatedAt: Date.now() } };
  });
});

export const updateCircle = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200);
  await requireMember(circleID, userID, true); const name = stringValue(data, "name", 30); const emoji = typeof data.emoji === "string" ? data.emoji.trim() : "";
  if (graphemes(emoji) > 1) fail("invalid-argument", "emoji is invalid.", "invalid-argument");
  await db.collection("circles").doc(circleID).update({ name, emoji, updatedAt: FieldValue.serverTimestamp() }); return { ok: true };
});

export const createCircleInvite = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200);
  const requestID = stringValue(data, "clientRequestID", 100); const requestRef = operationRequestRef(userID, "createCircleInvite", requestID);
  const { circle } = await requireMember(circleID, userID, true);
  if ((circle.data()?.memberCount ?? 0) >= (circle.data()?.maxMembers ?? MAX_MEMBERS)) fail("circle-full", "The circle is full.", "resource-exhausted");
  const active = await db.collection("circleInvites").where("circleID", "==", circleID).where("status", "==", "active").limit(MAX_ACTIVE_INVITES + 10).get();
  const activeCount = active.docs.filter(invite => (invite.data().expiresAt as Timestamp).toMillis() > Date.now()).length;
  if (activeCount >= MAX_ACTIVE_INVITES) fail("invite-limit", "Too many active invitations.", "resource-exhausted");
  const token = randomBytes(32).toString("base64url");
  const inviteHash = tokenHash(token);
  const managementID = randomBytes(18).toString("base64url");
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);
  await db.runTransaction(async transaction => {
    const previous = await transaction.get(requestRef);
    if (previous.exists) fail("operation-in-progress", "The original invitation token is no longer available.");
    transaction.create(db.collection("circleInvites").doc(inviteHash), { circleID, managementID, createdByUserID: userID, maxUses: 1, useCount: 0, expiresAt, status: "active", createdAt: FieldValue.serverTimestamp(), usedAt: null, usedByUserID: null });
    transaction.create(requestRef, operationRequest("createCircleInvite", userID, { circleID, managementID }));
  });
  return { inviteID: managementID, token, expiresAt: expiresAt.toMillis() };
});

export const listCircleInvites = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID, true);
  const snapshot = await db.collection("circleInvites").where("circleID", "==", circleID).orderBy("createdAt", "desc").limit(20).get();
  return { invites: snapshot.docs.map(doc => {
    const value = doc.data();
    const expiresAt = (value.expiresAt as Timestamp).toMillis();
    const status = value.status === "active" && expiresAt <= Date.now() ? "expired" : value.status;
    return { id: value.managementID, status, expiresAt };
  }).filter(invite => typeof invite.id === "string") };
});

export const revokeCircleInvite = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); const inviteID = stringValue(data, "inviteID", 100);
  await requireMember(circleID, userID, true);
  const matches = await db.collection("circleInvites").where("circleID", "==", circleID).where("managementID", "==", inviteID).limit(1).get();
  const snapshot = matches.docs[0];
  if (!snapshot) fail("invalid-invite", "Invitation not found.", "not-found");
  await snapshot.ref.update({ status: "revoked", revokedAt: FieldValue.serverTimestamp() }); return { ok: true };
});

async function preview(token: string) {
  const invite = await db.collection("circleInvites").doc(tokenHash(token)).get();
  if (!invite.exists) fail("invalid-invite", "Invitation is invalid.", "not-found");
  const value = invite.data()!; const expiresAt = value.expiresAt as Timestamp;
  let state = value.status === "used" ? "used" : value.status !== "active" ? "invalid" : expiresAt.toMillis() <= Date.now() ? "expired" : "active";
  const circle = await db.collection("circles").doc(value.circleID).get();
  if (!circle.exists) return { circleDisplayName: "Wamori", circleEmoji: "", ownerDisplayName: "メンバー", memberCount: 0, maxMembers: MAX_MEMBERS, expiresAt: expiresAt.toMillis(), state: "invalid" };
  if (circle.data()?.status !== "active") state = "invalid";
  if ((circle.data()?.memberCount ?? 0) >= (circle.data()?.maxMembers ?? MAX_MEMBERS)) state = "full";
  const ownerID = circle.data()?.ownerID;
  const owner = typeof ownerID === "string" ? await db.collection("users").doc(ownerID).get() : null;
  return { circleDisplayName: circle.data()?.name ?? "Wamori", circleEmoji: circle.data()?.emoji ?? "", ownerDisplayName: owner?.data()?.displayName ?? "メンバー",
    memberCount: circle.data()?.memberCount ?? 0, maxMembers: circle.data()?.maxMembers ?? MAX_MEMBERS, expiresAt: expiresAt.toMillis(), state };
}

export const previewCircleInvite = onCall(callableOptions, async request => {
  const data = input(request); if (!validToken(data.token)) fail("invalid-invite", "Invitation is invalid.", "invalid-argument"); return preview(data.token);
});

function escapeHTML(value: string): string {
  const entities: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" };
  return value.replace(/[&<>"']/g, character => entities[character]);
}

export const publicCircleInvitePreview = onRequest({ region: "asia-northeast1" }, async (request, response) => {
  const addressHash = createHash("sha256").update(request.ip || "unknown").digest("hex");
  try { await enforceRateLimit(addressHash, "public-preview", 60, 60 * 60 * 1000); } catch { response.status(429).type("text").send("Too many requests"); return; }
  response.set("Cache-Control", "private, max-age=0, no-store");
  response.set("X-Content-Type-Options", "nosniff");
  response.set("Referrer-Policy", "no-referrer");
  const token = request.path.split("/").filter(Boolean).at(-1) ?? "";
  let title = "Wamoriの輪への招待";
  let description = "大切な人と、今日をひとつずつ。";
  let canOpen = false;
  if (validToken(token)) {
    try {
      const result = await preview(token);
      title = `${result.circleEmoji ? `${result.circleEmoji} ` : ""}${result.circleDisplayName}への招待`;
      description = result.state === "active"
        ? `${result.ownerDisplayName}さんからWamoriの輪に招待されています。現在${result.memberCount}/${result.maxMembers}人です。`
        : "この招待は現在利用できません。";
      canOpen = result.state === "active";
    } catch {
      description = "この招待は現在利用できません。";
    }
  }
  const deepLink = `wamori://invite?token=${encodeURIComponent(token)}`;
  response.status(200).type("html").send(`<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${escapeHTML(title)}</title><meta name="description" content="${escapeHTML(description)}"><style>body{margin:0;background:#f8f3e8;color:#123f3b;font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:grid;place-items:center;min-height:100vh}.card{max-width:36rem;margin:24px;padding:40px;border-radius:28px;background:#fffaf0;box-shadow:0 14px 40px #123f3b18;text-align:center}.mark{font-size:52px}h1{font-size:26px}p{line-height:1.7;color:#49615e}a{display:inline-block;margin-top:18px;padding:14px 24px;border-radius:999px;background:#123f3b;color:white;text-decoration:none;font-weight:700}.disabled{opacity:.45;pointer-events:none}</style></head><body><main class="card"><div class="mark">◌</div><h1>${escapeHTML(title)}</h1><p>${escapeHTML(description)}</p><a class="${canOpen ? "" : "disabled"}" href="${escapeHTML(deepLink)}">Wamoriで開く</a></main></body></html>`);
});

export const joinCircleByInvite = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); await requireActiveUser(userID); if (!validToken(data.token)) fail("invalid-invite", "Invitation is invalid.", "invalid-argument");
  await enforceRateLimit(userID, "join-circle", 20, 60 * 60 * 1000);
  const requestID = stringValue(data, "clientRequestID", 100); const requestRef = operationRequestRef(userID, "joinCircleByInvite", requestID);
  const hash = tokenHash(data.token); const inviteRef = db.collection("circleInvites").doc(hash);
  return db.runTransaction(async transaction => {
    const previous = await transaction.get(requestRef);
    if (previous.exists) {
      const existing = await transaction.get(db.collection("circles").doc(previous.data()?.circleID));
      if (existing.exists) return { circle: circleDTO(existing.id, existing.data()!) };
    }
    const invite = await transaction.get(inviteRef); if (!invite.exists) fail("invalid-invite", "Invitation is invalid.", "not-found");
    const value = invite.data()!; if (value.status !== "active") fail(value.status === "used" ? "invite-used" : "invalid-invite", "Invitation is unavailable.");
    if ((value.expiresAt as Timestamp).toMillis() <= Date.now()) fail("invite-expired", "Invitation expired.");
    const circleRef = db.collection("circles").doc(value.circleID); const circle = await transaction.get(circleRef);
    if (!circle.exists || circle.data()?.status !== "active") fail("invalid-invite", "Invitation is invalid.");
    if ((circle.data()?.memberCount ?? 0) >= (circle.data()?.maxMembers ?? MAX_MEMBERS)) fail("circle-full", "The circle is full.", "resource-exhausted");
    const memberRef = circleRef.collection("members").doc(userID); const existing = await transaction.get(memberRef);
    if (existing.exists && existing.data()?.status === "active") fail("already-member", "Already a member.", "already-exists");
    const joined = await transaction.get(db.collection("users").doc(userID).collection("circleMemberships").where("status", "==", "active"));
    if (joined.size >= MAX_JOINED) fail("circle-limit", "Joined-circle limit reached.", "resource-exhausted");
    const ownerID = circle.data()?.ownerID as string;
    const blocks = await Promise.all([transaction.get(db.collection("blocks").doc(`${ownerID}_${userID}`)), transaction.get(db.collection("blocks").doc(`${userID}_${ownerID}`))]);
    if (blocks.some(block => block.exists)) fail("blocked-relationship", "This invitation cannot be joined.", "permission-denied");
    const now = FieldValue.serverTimestamp(); transaction.set(memberRef, { userID, role: "member", status: "active", joinedAt: now, updatedAt: now });
    transaction.set(db.collection("users").doc(userID).collection("circleMemberships").doc(circleRef.id), { circleID: circleRef.id, role: "member", status: "active", joinedAt: now, updatedAt: now });
    transaction.update(circleRef, { memberCount: FieldValue.increment(1), updatedAt: now }); transaction.update(inviteRef, { status: "used", useCount: 1, usedAt: now, usedByUserID: userID });
    transaction.create(requestRef, operationRequest("joinCircleByInvite", userID, { circleID: circleRef.id }));
    return { circle: circleDTO(circle.id, { ...circle.data(), memberCount: (circle.data()?.memberCount ?? 0) + 1 }) };
  });
});

export const createCircleEntry = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); await requireActiveUser(userID); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID);
  const body = typeof data.body === "string" ? data.body.trim() : ""; if (body.length > 500) fail("invalid-argument", "The entry is too long.", "invalid-argument");
  const mediaItems = await validateMedia(data.mediaItems ?? [], circleID, userID); if (!body && mediaItems.length === 0) fail("invalid-argument", "Text or an image is required.", "invalid-argument");
  const userRef = db.collection("users").doc(userID); const user = await userRef.get(); let zone = user.data()?.timeZoneIdentifier as string | undefined;
  if (!zone) { zone = stringValue(data, "timeZoneIdentifier", 100); dateKey(new Date(), zone); await userRef.set({ timeZoneIdentifier: zone, timeZoneUpdatedAt: FieldValue.serverTimestamp() }, { merge: true }); }
  const requestID = stringValue(data, "clientRequestID", 100); const requestRef = operationRequestRef(userID, "createCircleEntry", requestID);
  const key = dateKey(new Date(), zone); const entryRef = db.collection("circles").doc(circleID).collection("entries").doc(`${userID}_${key}`);
  const typing = metrics(data.typingMetrics, body.length); const assisted = data.aiAssisted === true;
  const age = user.data()?.createdAt instanceof Timestamp ? Math.max(Math.floor((Date.now() - user.data()!.createdAt.toMillis()) / 86_400_000), 0) : 0;
  const human = humanScore(typing, assisted, age); const prompt = promptFor(key, typeof data.locale === "string" ? data.locale : "ja");
  const didCreate = await db.runTransaction(async transaction => {
    const previous = await transaction.get(requestRef);
    if (previous.exists && previous.data()?.entryID === entryRef.id) return false;
    const existing = await transaction.get(entryRef); if (existing.exists && existing.data()?.isDeleted !== true) fail("entry-already-exists", "Today's entry already exists.", "already-exists");
    transaction.set(entryRef, { circleID, authorID: userID, dateKey: key, body, mediaItems, promptID: prompt.id, promptTextSnapshot: prompt.text,
      humanScore: human.score, humanBadge: human.badge, aiAssisted: assisted, ...typing, commentCount: 0,
      reactionCounts: { empathy: 0, insight: 0, cheer: 0 }, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), isDeleted: false, moderationStatus: "active", schemaVersion: 1 });
    transaction.update(db.collection("circles").doc(circleID), { updatedAt: FieldValue.serverTimestamp() });
    transaction.create(requestRef, operationRequest("createCircleEntry", userID, { circleID, entryID: entryRef.id }));
    return true;
  });
  if (didCreate) await createCircleNotification(circleID, userID, "circle_entry_created", entryRef.id); return { entryID: entryRef.id, dateKey: key };
});

export const updateCircleEntry = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID);
  const entryID = stringValue(data, "entryID", 300); const ref = db.collection("circles").doc(circleID).collection("entries").doc(entryID); const entry = await ref.get();
  if (!entry.exists || entry.data()?.authorID !== userID) fail("permission-denied", "Only the author can edit this entry.", "permission-denied");
  const user = await db.collection("users").doc(userID).get(); const zone = user.data()?.timeZoneIdentifier as string;
  if (entry.data()?.dateKey !== dateKey(new Date(), zone)) fail("entry-edit-window-closed", "Past entries cannot be edited.");
  const body = typeof data.body === "string" ? data.body.trim() : ""; if (body.length > 500) fail("invalid-argument", "The entry is too long.", "invalid-argument");
  const mediaItems = await validateMedia(data.mediaItems ?? [], circleID, userID); if (!body && mediaItems.length === 0) fail("invalid-argument", "Text or an image is required.", "invalid-argument");
  const typing = metrics(data.typingMetrics, body.length); const assisted = data.aiAssisted === true; const age = user.data()?.createdAt instanceof Timestamp ? Math.floor((Date.now() - user.data()!.createdAt.toMillis()) / 86_400_000) : 0; const human = humanScore(typing, assisted, age);
  const previousMedia = entry.data()?.mediaItems ?? [];
  const retainedPaths = new Set(mediaItems.map(media => media.storagePath));
  const removedMedia = previousMedia.filter((media: { storagePath?: string }) => typeof media.storagePath === "string" && !retainedPaths.has(media.storagePath));
  const batch = db.batch();
  batch.update(ref, { body, mediaItems, aiAssisted: assisted, ...typing, humanScore: human.score, humanBadge: human.badge, updatedAt: FieldValue.serverTimestamp() });
  if (removedMedia.length > 0) {
    batch.set(cleanupJobRef("entry-media-cleanup", circleID, `${entryID}:${Date.now()}`), cleanupJob("entry-media-cleanup", circleID, { entryID, mediaItems: removedMedia }));
  }
  await batch.commit();
  return { ok: true };
});

export const deleteCircleEntry = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID);
  const entryID = stringValue(data, "entryID", 300); const ref = db.collection("circles").doc(circleID).collection("entries").doc(entryID); const entry = await ref.get();
  if (!entry.exists || entry.data()?.authorID !== userID) fail("permission-denied", "Only the author can delete this entry.", "permission-denied");
  const batch = db.batch();
  batch.update(ref, { body: "", mediaItems: [], isDeleted: true, updatedAt: FieldValue.serverTimestamp() });
  batch.set(cleanupJobRef("entry-delete-cleanup", circleID, entryID), cleanupJob("entry-delete-cleanup", circleID, { entryID, mediaItems: entry.data()?.mediaItems ?? [] }));
  await batch.commit(); return { ok: true };
});

export const setCircleReaction = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID);
  const entryID = stringValue(data, "entryID", 300); const kind = stringValue(data, "kind", 20); if (!REACTIONS.has(kind)) fail("invalid-argument", "Invalid reaction.", "invalid-argument");
  const entryRef = db.collection("circles").doc(circleID).collection("entries").doc(entryID); const reactionRef = entryRef.collection("reactions").doc(userID);
  await db.runTransaction(async transaction => { const [entry, old] = await Promise.all([transaction.get(entryRef), transaction.get(reactionRef)]); if (!entry.exists || entry.data()?.isDeleted === true) fail("not-found", "Entry not found.", "not-found"); const oldKind = old.data()?.kind as string | undefined;
    if (oldKind === kind) { transaction.update(entryRef, { updatedAt: FieldValue.serverTimestamp(), [`reactionCounts.${kind}`]: FieldValue.increment(-1) }); transaction.delete(reactionRef); return; }
    const updates: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp(), [`reactionCounts.${kind}`]: FieldValue.increment(1) }; if (oldKind) updates[`reactionCounts.${oldKind}`] = FieldValue.increment(-1); transaction.update(entryRef, updates); transaction.set(reactionRef, { userID, kind, createdAt: old.data()?.createdAt ?? FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }); });
  return { ok: true };
});

export const createCircleComment = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID); const entryID = stringValue(data, "entryID", 300); const body = stringValue(data, "body", 500);
  const requestID = stringValue(data, "clientRequestID", 100); const requestRef = operationRequestRef(userID, "createCircleComment", requestID);
  const entryRef = db.collection("circles").doc(circleID).collection("entries").doc(entryID); const commentRef = entryRef.collection("comments").doc();
  const result = await db.runTransaction(async transaction => {
    const previous = await transaction.get(requestRef);
    if (previous.exists) return { commentID: previous.data()?.commentID as string, didCreate: false };
    const entry = await transaction.get(entryRef); if (!entry.exists || entry.data()?.isDeleted === true) fail("not-found", "Entry not found.", "not-found");
    transaction.create(commentRef, { circleID, entryID, userID, body, createdAt: FieldValue.serverTimestamp(), isDeleted: false, moderationStatus: "active" });
    transaction.update(entryRef, { commentCount: FieldValue.increment(1) });
    transaction.create(requestRef, operationRequest("createCircleComment", userID, { circleID, entryID, commentID: commentRef.id }));
    return { commentID: commentRef.id, didCreate: true };
  });
  if (result.didCreate) await createCircleNotification(circleID, userID, "circle_comment_created", entryID); return { commentID: result.commentID };
});

export const deleteCircleComment = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, userID); const entryID = stringValue(data, "entryID", 300); const commentID = stringValue(data, "commentID", 300);
  const entryRef = db.collection("circles").doc(circleID).collection("entries").doc(entryID); const commentRef = entryRef.collection("comments").doc(commentID);
  await db.runTransaction(async transaction => { const comment = await transaction.get(commentRef); if (!comment.exists || comment.data()?.userID !== userID) fail("permission-denied", "Only the author can delete this comment.", "permission-denied"); if (comment.data()?.isDeleted === true) return; transaction.update(commentRef, { body: "", isDeleted: true, updatedAt: FieldValue.serverTimestamp() }); transaction.update(entryRef, { commentCount: FieldValue.increment(-1) }); }); return { ok: true };
});

export const leaveCircle = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); const { member } = await requireMember(circleID, userID);
  if (member.data()?.role === "owner") fail("permission-denied", "Transfer ownership before leaving.", "permission-denied");
  await db.runTransaction(async transaction => { transaction.update(db.collection("circles").doc(circleID).collection("members").doc(userID), { status: "leaving", updatedAt: FieldValue.serverTimestamp() }); transaction.update(db.collection("users").doc(userID).collection("circleMemberships").doc(circleID), { status: "leaving", updatedAt: FieldValue.serverTimestamp() }); transaction.update(db.collection("circles").doc(circleID), { memberCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() }); transaction.set(cleanupJobRef("member-cleanup", circleID, userID), cleanupJob("member-cleanup", circleID, { reason: "leave", memberID: userID })); });
  return { ok: true };
});

export const transferCircleOwnership = onCall(callableOptions, async request => {
  const ownerID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); const targetID = stringValue(data, "userID", 200); await requireMember(circleID, ownerID, true);
  if (ownerID === targetID) return { ok: true }; const circleRef = db.collection("circles").doc(circleID);
  await db.runTransaction(async transaction => {
    const [target, targetOwned] = await Promise.all([
      transaction.get(circleRef.collection("members").doc(targetID)),
      transaction.get(db.collection("users").doc(targetID).collection("circleMemberships").where("role", "==", "owner").where("status", "==", "active"))
    ]);
    if (!target.exists || target.data()?.status !== "active") fail("invalid-member", "Target member is not active.", "invalid-argument");
    if (targetOwned.size >= MAX_OWNED) fail("circle-limit", "The target owns too many circles.", "resource-exhausted");
    const now = FieldValue.serverTimestamp(); transaction.update(circleRef, { ownerID: targetID, updatedAt: now }); transaction.update(circleRef.collection("members").doc(ownerID), { role: "member", updatedAt: now }); transaction.update(circleRef.collection("members").doc(targetID), { role: "owner", updatedAt: now }); transaction.update(db.collection("users").doc(ownerID).collection("circleMemberships").doc(circleID), { role: "member", updatedAt: now }); transaction.update(db.collection("users").doc(targetID).collection("circleMemberships").doc(circleID), { role: "owner", updatedAt: now });
  }); return { ok: true };
});

export const removeCircleMember = onCall(callableOptions, async request => {
  const ownerID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); const targetID = stringValue(data, "userID", 200); await requireMember(circleID, ownerID, true); if (targetID === ownerID) fail("invalid-member", "Owner cannot be removed.", "invalid-argument");
  const circleRef = db.collection("circles").doc(circleID); await db.runTransaction(async transaction => { const member = await transaction.get(circleRef.collection("members").doc(targetID)); if (!member.exists || member.data()?.status !== "active") fail("invalid-member", "Member is not active.", "not-found"); transaction.update(member.ref, { status: "removed", updatedAt: FieldValue.serverTimestamp() }); transaction.update(db.collection("users").doc(targetID).collection("circleMemberships").doc(circleID), { status: "removed", updatedAt: FieldValue.serverTimestamp() }); transaction.update(circleRef, { memberCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() }); transaction.set(cleanupJobRef("member-cleanup", circleID, targetID), cleanupJob("member-cleanup", circleID, { reason: "remove", memberID: targetID })); }); return { ok: true };
});

export const deleteCircle = onCall(callableOptions, async request => {
  const ownerID = uid(request); const data = input(request); const circleID = stringValue(data, "circleID", 200); await requireMember(circleID, ownerID, true); const circleRef = db.collection("circles").doc(circleID);
  await db.runTransaction(async transaction => { transaction.update(circleRef, { status: "deleting", updatedAt: FieldValue.serverTimestamp() }); transaction.set(cleanupJobRef("circle-delete", circleID), cleanupJob("circle-delete", circleID)); }); return { ok: true };
});

export const updateTimeZone = onCall(callableOptions, async request => {
  const userID = uid(request); const data = input(request); await requireActiveUser(userID); await enforceRateLimit(userID, "timezone", 10, 24 * 60 * 60 * 1000); const zone = stringValue(data, "timeZoneIdentifier", 100); dateKey(new Date(), zone); const ref = db.collection("users").doc(userID); const user = await ref.get(); const last = user.data()?.timeZoneUpdatedAt as Timestamp | undefined;
  if (last && Date.now() - last.toMillis() < 24 * 60 * 60 * 1000 && user.data()?.timeZoneIdentifier !== zone) fail("operation-in-progress", "Timezone can only be changed once per day.");
  await ref.set({ timeZoneIdentifier: zone, timeZoneUpdatedAt: FieldValue.serverTimestamp() }, { merge: true }); return { ok: true };
});

export const prepareCircleAccountDeletion = onCall(callableOptions, async request => {
  const userID = uid(request); await requireActiveUser(userID); await enforceRateLimit(userID, "account-delete", 5, 24 * 60 * 60 * 1000); const memberships = await db.collection("users").doc(userID).collection("circleMemberships").where("status", "==", "active").get();
  for (const membership of memberships.docs) {
    const circleID = membership.id;
    if (membership.data().role === "owner") {
      const others = await db.collection("circles").doc(circleID).collection("members").where("status", "==", "active").get();
      const target = others.docs.find(doc => doc.id !== userID);
      if (target) fail("ownership-transfer-required", "Transfer ownership before deleting the account.");
      await db.runTransaction(async transaction => { transaction.update(db.collection("circles").doc(circleID), { status: "deleting", updatedAt: FieldValue.serverTimestamp() }); transaction.set(cleanupJobRef("circle-delete", circleID), cleanupJob("circle-delete", circleID)); });
    } else {
      await db.runTransaction(async transaction => {
        const circleRef = db.collection("circles").doc(circleID);
        transaction.update(circleRef.collection("members").doc(userID), { status: "leaving", updatedAt: FieldValue.serverTimestamp() });
        transaction.update(membership.ref, { status: "leaving", updatedAt: FieldValue.serverTimestamp() });
        transaction.update(circleRef, { memberCount: FieldValue.increment(-1), updatedAt: FieldValue.serverTimestamp() });
        transaction.set(cleanupJobRef("member-cleanup", circleID, userID), cleanupJob("member-cleanup", circleID, { reason: "account-delete", memberID: userID }));
      });
    }
  }
  return { ok: true };
});

export const moderateCircleContent = onCall(callableOptions, async request => {
  const adminID = uid(request); await requireAdmin(adminID); await enforceRateLimit(adminID, "circle-moderation", 60, 60 * 60 * 1000);
  const data = input(request); const targetType = stringValue(data, "targetType", 30); const targetID = stringValue(data, "targetID", 700);
  const reason = stringValue(data, "reason", 200);
  const parts = targetID.split(":");
  if (targetType === "circle" && parts.length === 1) {
    await db.collection("circles").doc(parts[0]).update({ status: "suspended", moderationReason: reason, moderatedAt: FieldValue.serverTimestamp(), moderatedBy: adminID });
  } else if (targetType === "circleEntry" && parts.length === 2) {
    await db.collection("circles").doc(parts[0]).collection("entries").doc(parts[1]).update({ moderationStatus: "hidden", hiddenReason: reason, hiddenAt: FieldValue.serverTimestamp(), hiddenBy: adminID });
  } else if (targetType === "circleComment" && parts.length === 3) {
    await db.collection("circles").doc(parts[0]).collection("entries").doc(parts[1]).collection("comments").doc(parts[2]).update({ moderationStatus: "hidden", hiddenReason: reason, hiddenAt: FieldValue.serverTimestamp(), hiddenBy: adminID });
  } else {
    fail("invalid-argument", "Unsupported Circle report target.", "invalid-argument");
  }
  return { ok: true };
});

async function createCircleNotification(circleID: string, actorID: string, type: string, entryID: string) {
  const members = await db.collection("circles").doc(circleID).collection("members").where("status", "==", "active").get();
  let allowedRecipientIDs: Set<string> | null = null;
  if (type === "circle_comment_created") {
    const entry = await db.collection("circles").doc(circleID).collection("entries").doc(entryID).get();
    const authorID = entry.data()?.authorID;
    allowedRecipientIDs = typeof authorID === "string" ? new Set([authorID]) : new Set();
  }
  const batch = db.batch();
  const recipients: string[] = [];
  for (const member of members.docs) {
    if (member.id === actorID || (allowedRecipientIDs && !allowedRecipientIDs.has(member.id))) continue;
    recipients.push(member.id);
    const text = type === "circle_comment_created" ? "輪に新しいコメントがあります" : "輪に新しい記録があります";
    const ref = db.collection("notifications").doc(); batch.create(ref, { type, recipientID: member.id, actorID, circleID, entryID, text, isRead: false, createdAt: FieldValue.serverTimestamp() });
  }
  await batch.commit();
  if (!(await isCirclePushEnabled())) return;
  const body = type === "circle_comment_created" ? "輪に新しいコメントがあります" : "輪に新しい記録があります";
  for (const recipientID of recipients) {
    const [user, tokens] = await Promise.all([
      db.collection("users").doc(recipientID).get(),
      db.collection("fcmTokens").doc(recipientID).collection("tokens").where("isEnabled", "==", true).get()
    ]);
    if (user.data()?.notificationsEnabled === false || user.data()?.isDeleted === true || user.data()?.isSuspended === true) continue;
    const values = tokens.docs.map(token => token.data().token).filter((token): token is string => typeof token === "string" && token.length > 0);
    if (values.length === 0) continue;
    await getMessaging().sendEachForMulticast({
      tokens: values,
      notification: { title: "Wamori", body },
      data: { type: "circle_activity" },
      apns: { payload: { aps: { sound: "default" } } }
    });
  }
}

async function isCirclePushEnabled(): Promise<boolean> {
  if (circlePushCache.expiresAt > Date.now()) return circlePushCache.enabled;
  try {
    const template = await getRemoteConfig().getTemplate();
    const value = template.parameters.enable_circle_push?.defaultValue;
    const enabled = value && "value" in value && value.value === "true";
    circlePushCache = { enabled: !!enabled, expiresAt: Date.now() + 5 * 60 * 1000 };
  } catch {
    circlePushCache = { enabled: false, expiresAt: Date.now() + 60 * 1000 };
  }
  return circlePushCache.enabled;
}

async function runCleanup(job: QueryDocumentSnapshot) {
  const claimed = await db.runTransaction(async transaction => {
    const current = await transaction.get(job.ref);
    if (!current.exists || current.data()?.status === "complete") return null;
    const updatedAt = current.data()?.updatedAt as Timestamp | undefined;
    if (current.data()?.status === "running" && updatedAt && Date.now() - updatedAt.toMillis() < 10 * 60 * 1000) return null;
    transaction.update(job.ref, { status: "running", attempts: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    return current.data();
  });
  if (!claimed) return;
  const data = claimed;
  if (data.type === "entry-media-cleanup" || data.type === "entry-delete-cleanup") {
    for (const media of data.mediaItems ?? []) if (typeof media.storagePath === "string") await getStorage().bucket().file(media.storagePath).delete({ ignoreNotFound: true });
    if (data.type === "entry-delete-cleanup") {
      const entryRef = db.collection("circles").doc(data.circleID).collection("entries").doc(data.entryID);
      await db.recursiveDelete(entryRef.collection("comments"));
      await db.recursiveDelete(entryRef.collection("reactions"));
    }
  } else if (data.type === "circle-delete") {
    const circleRef = db.collection("circles").doc(data.circleID); const members = await circleRef.collection("members").get(); const batch = db.batch(); for (const member of members.docs) batch.delete(db.collection("users").doc(member.id).collection("circleMemberships").doc(data.circleID)); await batch.commit();
    const related = await Promise.all([
      db.collection("circleInvites").where("circleID", "==", data.circleID).get(),
      db.collection("notifications").where("circleID", "==", data.circleID).get(),
      db.collection("circleOperationRequests").where("circleID", "==", data.circleID).get()
    ]);
    for (const snapshot of related) for (const document of snapshot.docs) await document.ref.delete();
    await getStorage().bucket().deleteFiles({ prefix: `circleMedia/${data.circleID}/` }); await db.recursiveDelete(circleRef);
  } else if (data.type === "member-cleanup") {
    const circleRef = db.collection("circles").doc(data.circleID); const entries = await circleRef.collection("entries").get();
    for (const entry of entries.docs) {
      if (entry.data().authorID === data.memberID) { for (const media of entry.data().mediaItems ?? []) if (typeof media.storagePath === "string") await getStorage().bucket().file(media.storagePath).delete({ ignoreNotFound: true }); await db.recursiveDelete(entry.ref); }
      else { const reaction = entry.ref.collection("reactions").doc(data.memberID); const old = await reaction.get(); if (old.exists) { await reaction.delete(); await entry.ref.update({ [`reactionCounts.${old.data()?.kind}`]: FieldValue.increment(-1) }); } const comments = await entry.ref.collection("comments").where("userID", "==", data.memberID).where("isDeleted", "==", false).get(); for (const comment of comments.docs) await comment.ref.delete(); if (!comments.empty) await entry.ref.update({ commentCount: FieldValue.increment(-comments.size) }); }
    }
    await circleRef.collection("members").doc(data.memberID).delete(); await db.collection("users").doc(data.memberID).collection("circleMemberships").doc(data.circleID).delete();
  }
  await job.ref.update({ status: "complete", completedAt: FieldValue.serverTimestamp() });
}

export const processCircleOperationJobs = onSchedule({ schedule: "every 5 minutes", region: "asia-northeast1", maxInstances: 1 }, async () => {
  const [pending, running] = await Promise.all([
    db.collection("circleOperationJobs").where("status", "==", "pending").limit(10).get(),
    db.collection("circleOperationJobs").where("status", "==", "running").limit(10).get()
  ]);
  const jobs = [...pending.docs, ...running.docs];
  for (const job of jobs) { try { await runCleanup(job); } catch (error) { logger.error("Circle cleanup failed", { jobID: job.id, errorType: error instanceof Error ? error.name : "unknown" }); await job.ref.update({ status: "pending", lastErrorAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }); } }
});

export const cleanupCircleEphemeralRecords = onSchedule({ schedule: "every 24 hours", region: "asia-northeast1", maxInstances: 1 }, async () => {
  const now = Timestamp.now();
  const snapshots = await Promise.all([
    db.collection("circleRateLimits").where("expiresAt", "<=", now).limit(200).get(),
    db.collection("circleOperationRequests").where("expiresAt", "<=", now).limit(200).get(),
    db.collection("circleInvites").where("expiresAt", "<=", now).limit(200).get()
  ]);
  const batch = db.batch();
  let count = 0;
  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) {
      batch.delete(document.ref);
      count += 1;
    }
  }
  if (count > 0) await batch.commit();
  logger.info("Circle ephemeral records cleaned", { count });
});

// Pure policy hooks used by the local regression suite. Not re-exported as Cloud Functions.
export const circlePolicyForTesting = { dateKey, tokenHash, validToken, metrics, humanScore, promptFor };
