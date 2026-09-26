const test = require("node:test");
const assert = require("node:assert/strict");

const functions = require("../lib/index.js");

const endpoints = Object.entries(functions).filter(([, value]) => value && value.__endpoint);

test("every deployed function has an instance cap", () => {
  assert.ok(endpoints.length > 40);
  for (const [name, fn] of endpoints) {
    const max = fn.__endpoint.maxInstances;
    assert.ok(Number.isInteger(max) && max >= 1 && max <= 3, `${name} maxInstances=${max}`);
  }
});

test("scheduled functions run on a single instance", () => {
  for (const [name, fn] of endpoints) {
    if (fn.__endpoint.scheduleTrigger) assert.equal(fn.__endpoint.maxInstances, 1, name);
  }
});

test("daily digest is skipped unless explicitly enabled", async () => {
  delete process.env.WAMORI_DAILY_DIGEST_ENABLED;
  // Returns before touching Firestore; a query here would fail without an emulator.
  await functions.sendDailyDigest.run({ scheduleTime: new Date().toISOString() });
});
