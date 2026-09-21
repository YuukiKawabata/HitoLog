const assert = require("node:assert/strict");
const { test } = require("node:test");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const {
  createCircle,
  createCircleInvite,
  joinCircleByInvite,
  createCircleEntry,
  transferCircleOwnership,
} = require("../lib/circles.js");

const runsWithEmulator = !!process.env.FIRESTORE_EMULATOR_HOST;

function request(userID, data) {
  return {
    auth: { uid: userID, token: {} },
    app: { appId: "1:1234567890:ios:circle-tests", token: {} },
    data,
    instanceIdToken: undefined,
    rawRequest: {},
  };
}

test("Circle callables are transactional, idempotent, and preserve owner invariants", { skip: !runsWithEmulator }, async () => {
  const db = getFirestore();
  const suffix = `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const ownerID = `fn-owner-${suffix}`;
  const joinerIDs = [`fn-joiner-a-${suffix}`, `fn-joiner-b-${suffix}`];

  await Promise.all([ownerID, ...joinerIDs].map(userID => db.collection("users").doc(userID).set({
    displayName: "テストメンバー",
    isDeleted: false,
    isSuspended: false,
    createdAt: Timestamp.now(),
    timeZoneIdentifier: "Asia/Tokyo",
  })));

  const circleRequestID = `create-${suffix}`;
  const firstCircle = await createCircle.run(request(ownerID, {
    name: "テストの輪",
    emoji: "🌿",
    clientRequestID: circleRequestID,
  }));
  const retriedCircle = await createCircle.run(request(ownerID, {
    name: "再試行では変更されない",
    emoji: "",
    clientRequestID: circleRequestID,
  }));
  assert.equal(retriedCircle.circle.id, firstCircle.circle.id);
  assert.equal(retriedCircle.circle.name, "テストの輪");

  const circleID = firstCircle.circle.id;
  const invitation = await createCircleInvite.run(request(ownerID, {
    circleID,
    clientRequestID: `invite-${suffix}`,
  }));
  assert.match(invitation.token, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(invitation.inviteID, invitation.token);

  const joinResults = await Promise.allSettled(joinerIDs.map((userID, index) => joinCircleByInvite.run(request(userID, {
    token: invitation.token,
    clientRequestID: `join-${index}-${suffix}`,
  }))));
  const fulfilledJoins = joinResults
    .map((result, index) => ({ result, index }))
    .filter(item => item.result.status === "fulfilled");
  assert.equal(fulfilledJoins.length, 1, "a single-use invitation must admit exactly one concurrent caller");
  assert.equal(joinResults.filter(result => result.status === "rejected").length, 1);

  const joinedUserID = joinerIDs[fulfilledJoins[0].index];
  const entryPayload = {
    circleID,
    body: "今日の記録",
    mediaItems: [],
    typingMetrics: { inputDurationMs: 4_000, editCount: 1, deleteCount: 0, suspiciousBulkInputCount: 0 },
    aiAssisted: false,
    locale: "ja",
    timeZoneIdentifier: "Asia/Tokyo",
    clientRequestID: `entry-${suffix}`,
  };
  const entryResults = await Promise.all([
    createCircleEntry.run(request(ownerID, entryPayload)),
    createCircleEntry.run(request(ownerID, entryPayload)),
  ]);
  assert.equal(entryResults[0].entryID, entryResults[1].entryID);

  const [entries, notifications] = await Promise.all([
    db.collection("circles").doc(circleID).collection("entries").get(),
    db.collection("notifications").where("circleID", "==", circleID).where("type", "==", "circle_entry_created").get(),
  ]);
  assert.equal(entries.size, 1, "one user can create only one entry for the local date");
  assert.equal(notifications.size, 1, "an idempotent retry must not duplicate notifications");
  assert.equal(notifications.docs[0].data().text, "輪に新しい記録があります");

  await transferCircleOwnership.run(request(ownerID, { circleID, userID: joinedUserID }));
  const [circle, oldOwner, newOwner, oldMembership, newMembership] = await Promise.all([
    db.collection("circles").doc(circleID).get(),
    db.collection("circles").doc(circleID).collection("members").doc(ownerID).get(),
    db.collection("circles").doc(circleID).collection("members").doc(joinedUserID).get(),
    db.collection("users").doc(ownerID).collection("circleMemberships").doc(circleID).get(),
    db.collection("users").doc(joinedUserID).collection("circleMemberships").doc(circleID).get(),
  ]);
  assert.equal(circle.data().ownerID, joinedUserID);
  assert.equal(oldOwner.data().role, "member");
  assert.equal(newOwner.data().role, "owner");
  assert.equal(oldMembership.data().role, "member");
  assert.equal(newMembership.data().role, "owner");
});
