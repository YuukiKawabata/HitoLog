const assert = require("node:assert/strict");
const { X509Certificate } = require("node:crypto");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const test = require("node:test");

const { parsePurchasePurpose, productDefinition } = require("../lib/purchases.js");

test("registered products resolve to the expected purchase category", () => {
  assert.equal(productDefinition("jp.hitolog.article_unlock_300").kind, "article");
  assert.equal(productDefinition("jp.hitolog.creator_membership.v3.monthly_500").kind, "membership");
  assert.equal(productDefinition("jp.hitolog.support.once_1000").kind, "support");
  assert.equal(productDefinition("unknown.product"), undefined);
});

test("purchase purposes accept only bounded Firestore document IDs", () => {
  assert.deepEqual(parsePurchasePurpose({ kind: "article", articleID: "article-1" }), {
    kind: "article",
    articleID: "article-1"
  });
  assert.throws(() => parsePurchasePurpose({ kind: "article", articleID: "folder/article-1" }));
  assert.throws(() => parsePurchasePurpose({ kind: "membership", creatorID: "" }));
});

test("support purposes require a target for posts and articles", () => {
  assert.deepEqual(parsePurchasePurpose({
    kind: "support",
    recipientID: "creator-1",
    targetType: "profile"
  }), {
    kind: "support",
    recipientID: "creator-1",
    targetType: "profile"
  });
  assert.throws(() => parsePurchasePurpose({
    kind: "support",
    recipientID: "creator-1",
    targetType: "post"
  }));
  assert.throws(() => parsePurchasePurpose({
    kind: "support",
    recipientID: "creator-1",
    targetType: "profile",
    targetID: "post-1"
  }));
});

test("bundled Apple roots are valid DER certificates", () => {
  const certificateDirectory = join(__dirname, "..", "certs");
  for (const filename of [
    "AppleIncRootCertificate.cer.b64",
    "AppleRootCA-G2.cer.b64",
    "AppleRootCA-G3.cer.b64"
  ]) {
    const der = Buffer.from(readFileSync(join(certificateDirectory, filename), "utf8").trim(), "base64");
    const certificate = new X509Certificate(der);
    assert.match(certificate.subject, /Apple/);
  }
});
