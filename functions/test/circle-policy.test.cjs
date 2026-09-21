const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { circlePolicyForTesting } = require("../lib/circles.js");

test("Circle invitation tokens require a 256-bit base64url-sized value", () => {
  const valid = "a".repeat(43);
  assert.equal(circlePolicyForTesting.validToken(valid), true);
  assert.equal(circlePolicyForTesting.validToken("short"), false);
  assert.equal(circlePolicyForTesting.tokenHash(valid).length, 64);
  assert.notEqual(circlePolicyForTesting.tokenHash(valid), valid);
});

test("Circle date keys respect the registered IANA timezone", () => {
  const instant = new Date("2024-12-31T15:30:00.000Z");
  assert.equal(circlePolicyForTesting.dateKey(instant, "Asia/Tokyo"), "2025-01-01");
  assert.equal(circlePolicyForTesting.dateKey(instant, "UTC"), "2024-12-31");
  assert.throws(() => circlePolicyForTesting.dateKey(instant, "Not/A_Timezone"));
});

test("Circle typing metrics are bounded and the score never escapes 0...100", () => {
  const bounded = circlePolicyForTesting.metrics({
    inputDurationMs: -10,
    editCount: 999999,
    deleteCount: 4,
    suspiciousBulkInputCount: 999,
  }, 500);
  assert.deepEqual(bounded, {
    inputDurationMs: 0,
    characterCount: 500,
    editCount: 100000,
    deleteCount: 4,
    suspiciousBulkInputCount: 100,
  });
  const result = circlePolicyForTesting.humanScore(bounded, false, 0);
  assert.equal(result.score, 0);
  assert.equal(result.badge, "lowTrust");
});

test("daily Circle prompts are deterministic for a date and locale", () => {
  assert.deepEqual(
    circlePolicyForTesting.promptFor("2026-09-13", "ja"),
    circlePolicyForTesting.promptFor("2026-09-13", "ja-JP")
  );
});

test("every Circle mutation callable uses the App Check-enforced options", () => {
  const source = fs.readFileSync(path.resolve(__dirname, "../src/circles.ts"), "utf8");
  assert.match(source, /const callableOptions = \{ region: "asia-northeast1", enforceAppCheck: true \}/);
  const names = [
    "createCircle", "updateCircle", "createCircleInvite", "listCircleInvites", "revokeCircleInvite",
    "previewCircleInvite", "joinCircleByInvite", "createCircleEntry", "updateCircleEntry", "deleteCircleEntry",
    "setCircleReaction", "createCircleComment", "deleteCircleComment", "leaveCircle", "transferCircleOwnership",
    "removeCircleMember", "deleteCircle", "updateTimeZone", "prepareCircleAccountDeletion", "moderateCircleContent",
  ];
  for (const name of names) {
    assert.match(source, new RegExp(`export const ${name} = onCall\\(callableOptions,`), `${name} must enforce App Check`);
  }
});
