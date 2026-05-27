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
  throw new Error("Usage: node Scripts/backfill-comment-permission.mjs [--project PROJECT_ID] [--apply]");
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

let changed = 0;
let skipped = 0;

for (const document of documents) {
  const fields = document.fields ?? {};
  if (typeof fields.commentPermission?.stringValue === "string") {
    skipped += 1;
    continue;
  }

  changed += 1;
  if (applyChanges) {
    await patchPost(document.name);
  }
}

console.log(JSON.stringify({
  mode: applyChanges ? "applied" : "dry-run",
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

async function patchPost(documentName) {
  const url = new URL(`https://firestore.googleapis.com/v1/${documentName}`);
  url.searchParams.append("updateMask.fieldPaths", "commentPermission");

  const response = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      fields: {
        commentPermission: { stringValue: "everyone" }
      }
    })
  });

  if (!response.ok) {
    throw new Error(`Failed to update ${documentName}: ${response.status} ${await response.text()}`);
  }
}
