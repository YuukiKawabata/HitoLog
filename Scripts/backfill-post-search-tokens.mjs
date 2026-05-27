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
  throw new Error("Usage: node Scripts/backfill-post-search-tokens.mjs [--project PROJECT_ID] [--apply]");
}

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
const documents = await listDocuments("posts");
const shareCounts = countShares(documents);

let changed = 0;
let skipped = 0;

for (const document of documents) {
  const id = document.name.split("/").pop();
  const fields = document.fields ?? {};
  const body = stringValue(fields.body);
  const existingTopics = arrayStringValue(fields.topics);
  const topics = existingTopics.length > 0 ? existingTopics : extractTopics(body);
  const searchTokens = tokenizePost(body, topics);
  const shareType = stringValue(fields.shareType) || "original";
  const sourcePostID = stringValue(fields.sourcePostID);
  const sourceUserID = stringValue(fields.sourceUserID);
  const repostCount = shareCounts.reposts.get(id) ?? integerValue(fields.repostCount);
  const quoteCount = shareCounts.quotes.get(id) ?? integerValue(fields.quoteCount);

  const update = {
    topics,
    searchTokens,
    shareType,
    sourcePostID,
    sourceUserID,
    repostCount,
    quoteCount
  };

  if (!needsUpdate(fields, update)) {
    skipped += 1;
    continue;
  }

  changed += 1;
  if (applyChanges) {
    await patchPost(document.name, update);
  }
}

const mode = applyChanges ? "applied" : "dry-run";
console.log(JSON.stringify({
  mode,
  project,
  scannedPosts: documents.length,
  changedPosts: changed,
  skippedPosts: skipped
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

async function patchPost(documentName, update) {
  const url = new URL(`https://firestore.googleapis.com/v1/${documentName}`);
  for (const fieldPath of Object.keys(update)) {
    url.searchParams.append("updateMask.fieldPaths", fieldPath);
  }

  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ fields: encodeFields(update) })
  });

  if (!response.ok) {
    throw new Error(`Failed to update ${documentName}: ${response.status} ${await response.text()}`);
  }
}

function countShares(documents) {
  const reposts = new Map();
  const quotes = new Map();

  for (const document of documents) {
    const fields = document.fields ?? {};
    if (booleanValue(fields.isDeleted)) {
      continue;
    }

    const shareType = stringValue(fields.shareType);
    const sourcePostID = stringValue(fields.sourcePostID);
    if (!sourcePostID) {
      continue;
    }

    if (shareType === "repost") {
      reposts.set(sourcePostID, (reposts.get(sourcePostID) ?? 0) + 1);
    } else if (shareType === "quote") {
      quotes.set(sourcePostID, (quotes.get(sourcePostID) ?? 0) + 1);
    }
  }

  return { reposts, quotes };
}

function needsUpdate(fields, update) {
  return stringArrayChanged(arrayStringValue(fields.topics), update.topics)
    || stringArrayChanged(arrayStringValue(fields.searchTokens), update.searchTokens)
    || stringValue(fields.shareType) !== update.shareType
    || stringValue(fields.sourcePostID) !== update.sourcePostID
    || stringValue(fields.sourceUserID) !== update.sourceUserID
    || integerValue(fields.repostCount) !== update.repostCount
    || integerValue(fields.quoteCount) !== update.quoteCount;
}

function encodeFields(update) {
  return {
    topics: encodeStringArray(update.topics),
    searchTokens: encodeStringArray(update.searchTokens),
    shareType: { stringValue: update.shareType },
    sourcePostID: { stringValue: update.sourcePostID },
    sourceUserID: { stringValue: update.sourceUserID },
    repostCount: { integerValue: String(update.repostCount) },
    quoteCount: { integerValue: String(update.quoteCount) }
  };
}

function encodeStringArray(values) {
  return {
    arrayValue: {
      values: values.map((value) => ({ stringValue: value }))
    }
  };
}

function stringArrayChanged(current, next) {
  if (current.length !== next.length) {
    return true;
  }
  return current.some((value, index) => value !== next[index]);
}

function stringValue(value) {
  return typeof value?.stringValue === "string" ? value.stringValue : "";
}

function arrayStringValue(value) {
  return (value?.arrayValue?.values ?? [])
    .map((item) => stringValue(item))
    .filter((item) => item.length > 0);
}

function integerValue(value) {
  const rawValue = value?.integerValue ?? value?.doubleValue;
  const parsed = Number(rawValue);
  return Number.isFinite(parsed) ? parsed : 0;
}

function booleanValue(value) {
  return value?.booleanValue === true;
}

function extractTopics(text) {
  const seen = new Set();
  const topics = [];

  for (const rawToken of text.split(/\s+/u)) {
    const first = rawToken[0];
    if (first !== "#" && first !== "＃") {
      continue;
    }

    const topic = normalizeToken(rawToken.slice(1));
    if (topic.length < 2 || seen.has(topic)) {
      continue;
    }

    seen.add(topic);
    topics.push(topic);
    if (topics.length >= 8) {
      break;
    }
  }

  return topics;
}

function tokenizePost(text, topics = []) {
  const seen = new Set();
  const result = [];

  const append = (rawValue) => {
    const token = normalizeToken(rawValue);
    if (token.length < 2 || seen.has(token)) {
      return;
    }
    seen.add(token);
    result.push(token);
  };

  topics.forEach(append);

  const words = text.toLowerCase().split(/[^\p{Letter}\p{Number}_\-ー]+/u).filter(Boolean);
  words.forEach(append);

  const compact = normalizeToken(text);
  const characters = Array.from(compact);
  if (characters.length >= 2) {
    for (let size = 2; size <= Math.min(4, characters.length); size += 1) {
      if (result.length >= 80) {
        break;
      }
      for (let index = 0; index <= characters.length - size; index += 1) {
        append(characters.slice(index, index + size).join(""));
        if (result.length >= 80) {
          break;
        }
      }
    }
  }

  return result.slice(0, 80);
}

function normalizeToken(rawValue) {
  const value = Array.from(rawValue.toLowerCase())
    .filter((character) => /[\p{Letter}\p{Number}_\-ー]/u.test(character))
    .join("")
    .replace(/^[_\-ー]+|[_\-ー]+$/gu, "");
  return Array.from(value).slice(0, 32).join("");
}
