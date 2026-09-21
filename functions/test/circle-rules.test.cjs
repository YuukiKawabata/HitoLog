const fs = require("node:fs");
const path = require("node:path");
const { after, before, test } = require("node:test");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc, updateDoc } = require("firebase/firestore");
const { getBytes, ref, uploadBytes } = require("firebase/storage");

const runsWithEmulators = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_STORAGE_EMULATOR_HOST;
let environment;

before(async () => {
  if (!runsWithEmulators) return;
  const root = path.resolve(__dirname, "../..");
  environment = await initializeTestEnvironment({
    projectId: "hitolog-e22d2",
    firestore: { rules: fs.readFileSync(path.join(root, "firestore.rules"), "utf8") },
    storage: { rules: fs.readFileSync(path.join(root, "storage.rules"), "utf8") },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const database = context.firestore();
    const activeUser = { isDeleted: false, isSuspended: false };
    await Promise.all([
      setDoc(doc(database, "users/member"), activeUser),
      setDoc(doc(database, "users/outsider"), activeUser),
      setDoc(doc(database, "users/leaving"), activeUser),
      setDoc(doc(database, "circles/circle-a"), { status: "active", ownerID: "member" }),
      setDoc(doc(database, "circles/circle-a/members/member"), { status: "active", role: "owner" }),
      setDoc(doc(database, "circles/circle-a/members/leaving"), { status: "leaving", role: "member" }),
      setDoc(doc(database, "circles/circle-a/entries/member_2026-09-13"), { circleID: "circle-a", authorID: "member", isDeleted: false }),
      setDoc(doc(database, "posts/legacy-public"), { userID: "member", isDeleted: false }),
    ]);
  });
});

after(async () => {
  if (environment) await environment.cleanup();
});

test("active member can read Circle data", { skip: !runsWithEmulators }, async () => {
  const database = environment.authenticatedContext("member").firestore();
  await assertSucceeds(getDoc(doc(database, "circles/circle-a")));
  await assertSucceeds(getDoc(doc(database, "circles/circle-a/entries/member_2026-09-13")));
});

test("non-member and leaving member immediately lose Circle reads", { skip: !runsWithEmulators }, async () => {
  const outsider = environment.authenticatedContext("outsider").firestore();
  const leaving = environment.authenticatedContext("leaving").firestore();
  await assertFails(getDoc(doc(outsider, "circles/circle-a")));
  await assertFails(getDoc(doc(leaving, "circles/circle-a")));
});

test("clients cannot forge membership or mutate Circle documents", { skip: !runsWithEmulators }, async () => {
  const outsider = environment.authenticatedContext("outsider").firestore();
  const member = environment.authenticatedContext("member").firestore();
  await assertFails(setDoc(doc(outsider, "circles/circle-a/members/outsider"), { status: "active", role: "member" }));
  await assertFails(updateDoc(doc(member, "circles/circle-a"), { name: "forged" }));
  await assertFails(updateDoc(doc(member, "circles/circle-a/entries/member_2026-09-13"), { body: "forged" }));
});

test("existing public posts remain readable to signed-in users", { skip: !runsWithEmulators }, async () => {
  const database = environment.authenticatedContext("outsider").firestore();
  await assertSucceeds(getDoc(doc(database, "posts/legacy-public")));
});

test("Circle Storage accepts only member-owned JPEG drafts", { skip: !runsWithEmulators }, async () => {
  const memberStorage = environment.authenticatedContext("member").storage();
  const outsiderStorage = environment.authenticatedContext("outsider").storage();
  const jpegReference = ref(memberStorage, "circleMedia/circle-a/drafts/member/valid.jpg");
  await assertSucceeds(uploadBytes(jpegReference, new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), { contentType: "image/jpeg" }));
  await assertFails(uploadBytes(jpegReference, new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), { contentType: "image/jpeg" }));
  await assertFails(uploadBytes(ref(memberStorage, "circleMedia/circle-a/drafts/member/invalid.png"), new Uint8Array([1, 2, 3]), { contentType: "image/png" }));
  await assertFails(uploadBytes(ref(memberStorage, "circleMedia/circle-a/drafts/member/too-large.jpg"), new Uint8Array(10 * 1024 * 1024 + 1), { contentType: "image/jpeg" }));
  await assertFails(uploadBytes(ref(outsiderStorage, "circleMedia/circle-a/drafts/outsider/forged.jpg"), new Uint8Array([0xff, 0xd8]), { contentType: "image/jpeg" }));
  await assertFails(getBytes(ref(outsiderStorage, "circleMedia/circle-a/drafts/member/valid.jpg")));
});
