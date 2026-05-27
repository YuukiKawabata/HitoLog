#!/usr/bin/env node

import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const args = new Set(process.argv.slice(2));
const applyChanges = args.has("--apply");
const projectArgIndex = process.argv.indexOf("--project");
const project = projectArgIndex >= 0 ? process.argv[projectArgIndex + 1] : "hitolog-e22d2";

if (!project || project.startsWith("--")) {
  throw new Error("Usage: node Scripts/backfill-topic-rooms.mjs [--project PROJECT_ID] [--apply]");
}

const officialRooms = [
  ["言葉", "言葉を書く人", "その場で考えて書いた言葉を読み合う部屋です。"],
  ["日常ログ", "日常ログ", "今日の出来事や生活の記録を残す部屋です。"],
  ["創作", "創作", "物語、作品、アイデアを育てる部屋です。"],
  ["学び", "学び", "学習メモや気づきを共有する部屋です。"]
];

const firebaseToolsRequire = createFirebaseToolsRequire();
const auth = firebaseToolsRequire("firebase-tools/lib/auth");
const apiv2 = firebaseToolsRequire("firebase-tools/lib/apiv2");

const options = { project };
const account = auth.getProjectDefaultAccount(process.cwd()) || auth.getGlobalDefaultAccount();
if (account) {
  auth.setActiveAccount(options, account);
}

const token = await apiv2.getAccessToken();
const baseURL = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
const posts = await listDocuments("posts");
const existingTopicRooms = await listDocuments("topicRooms");
const rooms = new Map();

for (const document of existingTopicRooms) {
  const fields = document.fields ?? {};
  const topic = fields.topic?.stringValue ?? document.name.split("/").pop();
  if (!topic) {
    continue;
  }
  rooms.set(topic, {
    topic,
    title: fields.title?.stringValue ?? `#${topic}`,
    description: fields.description?.stringValue ?? "",
    postCount: 0,
    followerCount: Number(fields.followerCount?.integerValue ?? 0),
    lastPostAt: null,
    createdAt: fields.createdAt?.timestampValue ?? null,
    isOfficial: fields.isOfficial?.booleanValue === true
  });
}

for (const [topic, title, description] of officialRooms) {
  const existing = rooms.get(topic);
  rooms.set(topic, {
    topic,
    title,
    description,
    postCount: 0,
    followerCount: existing?.followerCount ?? 0,
    lastPostAt: null,
    createdAt: existing?.createdAt ?? null,
    isOfficial: true
  });
}

for (const post of posts) {
  const fields = post.fields ?? {};
  if (fields.isDeleted?.booleanValue === true) {
    continue;
  }
  if ((fields.moderationStatus?.stringValue ?? "active") !== "active") {
    continue;
  }

  const createdAt = fields.createdAt?.timestampValue ?? null;
  const topics = fields.topics?.arrayValue?.values?.map((value) => value.stringValue).filter(Boolean) ?? [];
  for (const topic of new Set(topics)) {
    const room = rooms.get(topic) ?? {
      topic,
      title: `#${topic}`,
      description: "",
      postCount: 0,
      followerCount: 0,
      lastPostAt: null,
      createdAt: null,
      isOfficial: false
    };
    room.postCount += 1;
    if (createdAt && (!room.lastPostAt || createdAt > room.lastPostAt)) {
      room.lastPostAt = createdAt;
    }
    rooms.set(topic, room);
  }
}

if (applyChanges) {
  for (const room of rooms.values()) {
    await patchTopicRoom(room);
  }
}

console.log(JSON.stringify({
  mode: applyChanges ? "applied" : "dry-run",
  project,
  scannedPosts: posts.length,
  existingTopicRooms: existingTopicRooms.length,
  topicRooms: rooms.size,
  officialRooms: officialRooms.length
}, null, 2));

function createFirebaseToolsRequire() {
  const candidates = [
    "/opt/homebrew/lib/node_modules/firebase-tools/package.json",
    "/usr/local/lib/node_modules/firebase-tools/package.json",
    path.join(process.env.HOME ?? "", ".npm-global/lib/node_modules/firebase-tools/package.json"),
    path.join(__dirname, "../node_modules/firebase-tools/package.json")
  ];

  for (const candidate of candidates) {
    try {
      return createRequire(candidate);
    } catch {
      // Try the next known global install location.
    }
  }

  try {
    require.resolve("firebase-tools");
    return require;
  } catch {
    throw new Error("firebase-tools was not found. Install or log in with Firebase CLI, then rerun this script.");
  }
}

async function listDocuments(collectionName) {
  const result = [];
  let pageToken = "";

  do {
    const url = new URL(`${baseURL}/${collectionName}`);
    url.searchParams.set("pageSize", "300");
    if (pageToken) {
      url.searchParams.set("pageToken", pageToken);
    }

    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` }
    });
    if (!response.ok) {
      throw new Error(`Failed to list ${collectionName}: ${response.status} ${await response.text()}`);
    }

    const payload = await response.json();
    result.push(...(payload.documents ?? []));
    pageToken = payload.nextPageToken ?? "";
  } while (pageToken);

  return result;
}

async function patchTopicRoom(room) {
  const url = new URL(`${baseURL}/topicRooms/${encodeURIComponent(room.topic)}`);
  for (const field of [
    "topic",
    "title",
    "description",
    "postCount",
    "followerCount",
    "lastPostAt",
    "createdAt",
    "updatedAt",
    "isOfficial",
    "moderationStatus"
  ]) {
    url.searchParams.append("updateMask.fieldPaths", field);
  }

  const now = new Date().toISOString();
  const fields = {
    topic: { stringValue: room.topic },
    title: { stringValue: room.title },
    description: { stringValue: room.description },
    postCount: { integerValue: String(room.postCount) },
    followerCount: { integerValue: String(room.followerCount) },
    createdAt: { timestampValue: room.createdAt ?? now },
    updatedAt: { timestampValue: now },
    isOfficial: { booleanValue: room.isOfficial },
    moderationStatus: { stringValue: "active" }
  };
  if (room.lastPostAt) {
    fields.lastPostAt = { timestampValue: room.lastPostAt };
  } else {
    fields.lastPostAt = { nullValue: null };
  }

  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ fields })
  });

  if (!response.ok) {
    throw new Error(`Failed to update topicRooms/${room.topic}: ${response.status} ${await response.text()}`);
  }
}
