const fs = require("node:fs");
const path = require("node:path");
const { after, before, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc } = require("firebase/firestore");
const { deleteObject, getBytes, ref, uploadBytes } = require("firebase/storage");

// 低コスト保管モード: 旧SNSは読み取り専用（Documentation/COST_SAFE_MODE.md）。
const runsWithEmulators = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_STORAGE_EMULATOR_HOST;
let environment;

before(async () => {
  if (!runsWithEmulators) return;
  const root = path.resolve(__dirname, "../..");
  environment = await initializeTestEnvironment({
    projectId: "demo-legacy-readonly",
    firestore: { rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8") },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    await Promise.all([
      setDoc(doc(database, "users/alice"), { displayName: "Alice", location: "京都", isDeleted: false, isSuspended: false }),
      setDoc(doc(database, "users/bob"), { displayName: "Bob", isDeleted: false, isSuspended: false }),
      setDoc(doc(database, "posts/p1"), { userID: "alice", body: "hello", isDeleted: false, commentPermission: "everyone" }),
      setDoc(doc(database, "articles/a1"), { userID: "alice", title: "t", freePreviewBody: "b", status: "published", isDeleted: false }),
      setDoc(doc(database, "comments/c1"), { postID: "p1", userID: "alice", body: "c", isDeleted: false }),
      setDoc(doc(database, "likes/p1_alice"), { postID: "p1", userID: "alice" }),
      setDoc(doc(database, "follows/alice_bob"), { followerID: "alice", followeeID: "bob" }),
    ]);
    await uploadBytes(ref(context.storage(), "postMedia/alice/p1/old.jpg"), new Uint8Array([1, 2, 3]), { contentType: "image/jpeg" });
  });
});

after(async () => {
  if (environment) await environment.cleanup();
});

test("legacy posts stay readable", { skip: !runsWithEmulators }, async () => {
  const bob = environment.authenticatedContext("bob").firestore();
  await assertSucceeds(getDoc(doc(bob, "posts/p1")));
  await assertSucceeds(getDoc(doc(bob, "articles/a1")));
});

test("legacy social writes that trigger Functions are rejected", { skip: !runsWithEmulators }, async () => {
  const alice = environment.authenticatedContext("alice").firestore();
  const now = serverTimestamp();
  await assertFails(setDoc(doc(alice, "posts/p2"), {
    userID: "alice", body: "new", mediaItems: [], shareType: "original", commentPermission: "everyone",
    likeCount: 0, commentCount: 0, repostCount: 0, quoteCount: 0, reactionCounts: {},
    createdAt: now, updatedAt: now, isDeleted: false, moderationStatus: "active",
  }));
  await assertFails(updateDoc(doc(alice, "posts/p1"), { body: "edited", updatedAt: now }));
  await assertFails(setDoc(doc(alice, "comments/c2"), { postID: "p1", userID: "alice", body: "c", createdAt: now, updatedAt: now, isDeleted: false, moderationStatus: "active" }));
  await assertFails(setDoc(doc(alice, "likes/p1_bob"), { postID: "p1", userID: "alice", createdAt: now }));
  await assertFails(setDoc(doc(alice, "reactions/p1_alice"), { postID: "p1", userID: "alice", kind: "empathy", createdAt: now }));
  await assertFails(setDoc(doc(alice, "follows/alice_carol"), { followerID: "alice", followeeID: "carol", createdAt: now }));
  await assertFails(setDoc(doc(alice, "topicFollows/alice_swift"), { userID: "alice", topic: "swift", createdAt: now }));
  await assertFails(updateDoc(doc(alice, "articles/a1"), { title: "edited", updatedAt: now }));
});

test("owners can still remove their own legacy content", { skip: !runsWithEmulators }, async () => {
  const alice = environment.authenticatedContext("alice").firestore();
  const now = serverTimestamp();
  await assertSucceeds(updateDoc(doc(alice, "posts/p1"), { isDeleted: true, updatedAt: now }));
  await assertSucceeds(updateDoc(doc(alice, "articles/a1"), { isDeleted: true, updatedAt: now }));
  await assertSucceeds(updateDoc(doc(alice, "comments/c1"), { isDeleted: true, updatedAt: now }));
  await assertSucceeds(deleteDoc(doc(alice, "likes/p1_alice")));
  await assertSucceeds(deleteDoc(doc(alice, "follows/alice_bob")));
});

test("profile edits and safety actions keep working", { skip: !runsWithEmulators }, async () => {
  const alice = environment.authenticatedContext("alice").firestore();
  await assertSucceeds(updateDoc(doc(alice, "users/alice"), { location: "大阪", updatedAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(alice, "blocks/alice_bob"), { blockerID: "alice", blockedUserID: "bob", createdAt: serverTimestamp() }));
});

test("legacy media uploads are rejected but existing media stays readable and deletable", { skip: !runsWithEmulators }, async () => {
  const alice = environment.authenticatedContext("alice").storage();
  const bob = environment.authenticatedContext("bob").storage();
  await assertFails(uploadBytes(ref(alice, "postMedia/alice/p1/new.jpg"), new Uint8Array([1]), { contentType: "image/jpeg" }));
  await assertFails(uploadBytes(ref(alice, "postMedia/alice/p1/thumbs/new.jpg"), new Uint8Array([1]), { contentType: "image/jpeg" }));
  await assertSucceeds(getBytes(ref(bob, "postMedia/alice/p1/old.jpg")));
  await assertSucceeds(deleteObject(ref(alice, "postMedia/alice/p1/old.jpg")));
});
