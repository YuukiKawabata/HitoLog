import { initializeApp } from "firebase-admin/app";
import { DocumentReference, FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

initializeApp();
setGlobalOptions({ region: "asia-northeast1" });

const db = getFirestore();

type NotificationType = "comment" | "like" | "follow" | "repost" | "quote";
type ModerationStatus = "active" | "reviewRequired" | "hidden";
type PostShareType = "original" | "repost" | "quote";
type CommentPermission = "everyone" | "following" | "closed";

const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const POST_LIMIT_PER_HOUR = 20;
const COMMENT_LIMIT_PER_HOUR = 80;
const FOLLOW_LIMIT_PER_HOUR = 120;

interface PostRecord {
  userID: string;
  body?: string;
  mediaItems?: Array<{ type?: string; downloadURL?: string }>;
  moderationStatus?: ModerationStatus;
  shareType?: PostShareType;
  sourcePostID?: string;
  sourceUserID?: string;
  isDeleted?: boolean;
  commentPermission?: CommentPermission;
  topics?: string[];
  createdAt?: Timestamp;
  topicCounted?: boolean;
}

interface CommentRecord {
  postID: string;
  userID: string;
  body: string;
  isDeleted?: boolean;
  moderationStatus?: ModerationStatus;
  counted?: boolean;
}

interface LikeRecord {
  postID: string;
  userID: string;
}

interface FollowRecord {
  followerID: string;
  followeeID: string;
  counted?: boolean;
}

interface TopicFollowRecord {
  userID: string;
  topic: string;
  counted?: boolean;
}

interface PublicPageResponse {
  status(code: number): PublicPageResponse;
  set(field: string, value: string): PublicPageResponse;
  send(body: string): void;
}

export const onPostCreated = onDocumentCreated("posts/{postID}", async (event) => {
  const post = event.data?.data() as PostRecord | undefined;
  if (!post) {
    return;
  }

  const postRef = db.collection("posts").doc(event.params.postID);
  if (!(await isUserActive(post.userID))) {
    await hideDocument(postRef, "suspended_user");
    return;
  }

  if (await exceedsRecentCount("posts", "userID", post.userID, POST_LIMIT_PER_HOUR)) {
    await hideDocument(postRef, "rate_limit");
    return;
  }

  await handlePostShareCreated(post, event.params.postID);
  await markPostTopicsCounted(postRef, post);
});

export const onPostUpdated = onDocumentUpdated("posts/{postID}", async (event) => {
  const before = event.data?.before.data() as PostRecord | undefined;
  const after = event.data?.after.data() as PostRecord | undefined;
  if (!before || !after) {
    return;
  }

  if (before.isDeleted !== true && after.isDeleted === true) {
    await updateShareCount(after, -1);
  }

  await syncPostTopicCounts(event.params.postID, before, after);
});

export const onCommentCreated = onDocumentCreated("comments/{commentID}", async (event) => {
  const comment = event.data?.data() as CommentRecord | undefined;
  if (!comment) {
    return;
  }

  const commentRef = db.collection("comments").doc(event.params.commentID);
  if (!(await isUserActive(comment.userID))) {
    await hideDocument(commentRef, "suspended_user");
    return;
  }

  if (await exceedsRecentCount("comments", "userID", comment.userID, COMMENT_LIMIT_PER_HOUR)) {
    await hideDocument(commentRef, "rate_limit");
    return;
  }

  const postRef = db.collection("posts").doc(comment.postID);
  const postSnapshot = await postRef.get();
  const post = postSnapshot.data() as PostRecord | undefined;
  if (!post) {
    logger.warn("Comment created for missing post", { commentID: event.params.commentID, postID: comment.postID });
    await hideDocument(commentRef, "missing_post");
    return;
  }

  if (!(await canCreateComment(comment, post))) {
    await hideDocument(commentRef, "comment_permission");
    return;
  }

  await postRef.update({
    commentCount: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp()
  });
  await commentRef.set({ counted: true }, { merge: true });

  await createAndSendNotification({
    type: "comment",
    recipientID: post.userID,
    actorID: comment.userID,
    postID: comment.postID,
    body: comment.body
  });
});

export const onCommentUpdated = onDocumentUpdated("comments/{commentID}", async (event) => {
  const before = event.data?.before.data() as CommentRecord | undefined;
  const after = event.data?.after.data() as CommentRecord | undefined;
  if (!before || !after || before.postID !== after.postID) {
    return;
  }

  const beforeCounted = before.counted === true && isCountableComment(before);
  const afterCounted = after.counted === true && isCountableComment(after);
  if (beforeCounted && !afterCounted) {
    await adjustCommentCount(after.postID, -1);
    if (after.counted === true) {
      await db.collection("comments").doc(event.params.commentID).set({ counted: false }, { merge: true });
    }
  }
});

export const onLikeCreated = onDocumentCreated("likes/{likeID}", async (event) => {
  const like = event.data?.data() as LikeRecord | undefined;
  if (!like) {
    return;
  }

  const postRef = db.collection("posts").doc(like.postID);
  const postSnapshot = await postRef.get();
  const post = postSnapshot.data() as PostRecord | undefined;
  if (!post) {
    logger.warn("Like created for missing post", { likeID: event.params.likeID, postID: like.postID });
    return;
  }

  await postRef.update({
    likeCount: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp()
  });

  await createAndSendNotification({
    type: "like",
    recipientID: post.userID,
    actorID: like.userID,
    postID: like.postID
  });
});

export const onLikeDeleted = onDocumentDeleted("likes/{likeID}", async (event) => {
  const like = event.data?.data() as LikeRecord | undefined;
  if (!like) {
    return;
  }

  await db.collection("posts").doc(like.postID).update({
    likeCount: FieldValue.increment(-1),
    updatedAt: FieldValue.serverTimestamp()
  });
});

export const onFollowCreated = onDocumentCreated("follows/{followID}", async (event) => {
  const followRef = db.collection("follows").doc(event.params.followID);
  const follow = event.data?.data() as FollowRecord | undefined;
  if (!follow) {
    return;
  }

  if (follow.followerID === follow.followeeID) {
    await followRef.delete();
    return;
  }

  if (!(await isUserActive(follow.followerID)) || !(await isUserActive(follow.followeeID))) {
    await followRef.delete();
    return;
  }

  if (await exceedsRecentCount("follows", "followerID", follow.followerID, FOLLOW_LIMIT_PER_HOUR)) {
    await followRef.delete();
    return;
  }

  await updateFollowCounts(follow.followerID, follow.followeeID, 1);
  await followRef.set({ counted: true }, { merge: true });

  await createAndSendNotification({
    type: "follow",
    recipientID: follow.followeeID,
    actorID: follow.followerID
  });
});

export const onFollowDeleted = onDocumentDeleted("follows/{followID}", async (event) => {
  const follow = event.data?.data() as FollowRecord | undefined;
  if (!follow || follow.followerID === follow.followeeID || follow.counted !== true) {
    return;
  }

  await updateFollowCounts(follow.followerID, follow.followeeID, -1);
});

export const onTopicFollowCreated = onDocumentCreated("topicFollows/{followID}", async (event) => {
  const followRef = db.collection("topicFollows").doc(event.params.followID);
  const follow = event.data?.data() as TopicFollowRecord | undefined;
  if (!follow || !isValidTopic(follow.topic)) {
    await followRef.delete();
    return;
  }

  if (!(await isUserActive(follow.userID))) {
    await followRef.delete();
    return;
  }

  await adjustTopicFollowerCount(follow.topic, 1);
  await followRef.set({ counted: true }, { merge: true });
});

export const onTopicFollowDeleted = onDocumentDeleted("topicFollows/{followID}", async (event) => {
  const follow = event.data?.data() as TopicFollowRecord | undefined;
  if (!follow || follow.counted !== true || !isValidTopic(follow.topic)) {
    return;
  }

  await adjustTopicFollowerCount(follow.topic, -1);
});

export const publicPage = onRequest(async (request, response) => {
  const path = decodeURIComponent(request.path || new URL(request.url, "https://hitolog.local").pathname);
  const host = request.get("host") || "hitolog-e22d2.web.app";
  const baseURL = `https://${host}`;

  if (path.startsWith("/p/")) {
    await renderPostPage(path.replace("/p/", "").split("/")[0], baseURL, response);
    return;
  }

  if (path.startsWith("/t/")) {
    await renderTopicPage(path.replace("/t/", "").split("/")[0], baseURL, response);
    return;
  }

  response.status(404).send(renderBaseHTML({
    title: "HitoLog",
    description: "HitoLogは、自分の言葉で書くSNSです。",
    canonicalURL: baseURL,
    body: "<main><h1>HitoLog</h1><p>ページが見つかりません。</p></main>"
  }));
});

async function createAndSendNotification(input: {
  type: NotificationType;
  recipientID: string;
  actorID: string;
  postID?: string;
  body?: string;
}) {
  if (!input.recipientID || !input.actorID) {
    return;
  }

  if (input.recipientID === input.actorID) {
    return;
  }

  const [recipientSnapshot, actorSnapshot, blockSnapshot, muteSnapshot] = await Promise.all([
    db.collection("users").doc(input.recipientID).get(),
    db.collection("users").doc(input.actorID).get(),
    db.collection("blocks").doc(`${input.recipientID}_${input.actorID}`).get(),
    db.collection("mutes").doc(`${input.recipientID}_${input.actorID}`).get()
  ]);

  const recipient = recipientSnapshot.data();
  const actor = actorSnapshot.data();
  if (!recipient || recipient.notificationsEnabled === false || recipient.isDeleted === true || recipient.isSuspended === true) {
    return;
  }

  if (!actor || actor.isDeleted === true || actor.isSuspended === true || blockSnapshot.exists || muteSnapshot.exists) {
    return;
  }

  const actorName = typeof actor?.displayName === "string" ? actor.displayName : "HitoLog";
  const notificationText = notificationTextFor(input.type, actorName);

  const notificationData: { [key: string]: unknown } = {
    type: input.type,
    recipientID: input.recipientID,
    actorID: input.actorID,
    text: notificationText,
    isRead: false,
    createdAt: FieldValue.serverTimestamp()
  };
  if (input.postID) {
    notificationData.postID = input.postID;
  }

  await db.collection("notifications").add(notificationData);

  const tokenSnapshot = await db.collection("fcmTokens")
    .doc(input.recipientID)
    .collection("tokens")
    .where("isEnabled", "==", true)
    .get();

  const tokens = tokenSnapshot.docs
    .map((doc) => doc.data().token)
    .filter((token): token is string => typeof token === "string" && token.length > 0);

  if (tokens.length === 0) {
    return;
  }

  const messageData: Record<string, string> = {
    type: input.type,
    actorID: input.actorID
  };
  if (input.postID) {
    messageData.postID = input.postID;
  }

  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "HitoLog",
      body: notificationText
    },
    data: messageData,
    apns: {
      payload: {
        aps: {
          sound: "default"
        }
      }
    }
  });
}

async function handlePostShareCreated(post: PostRecord, postID: string) {
  if (post.shareType !== "repost" && post.shareType !== "quote") {
    return;
  }

  await updateShareCount(post, 1);
  await createAndSendNotification({
    type: post.shareType,
    recipientID: post.sourceUserID ?? "",
    actorID: post.userID,
    postID: post.sourcePostID,
    body: post.body
  });

  logger.info("Share post processed", { postID, shareType: post.shareType, sourcePostID: post.sourcePostID });
}

async function updateShareCount(post: PostRecord, amount: 1 | -1) {
  if ((post.shareType !== "repost" && post.shareType !== "quote") || !post.sourcePostID) {
    return;
  }

  const field = post.shareType === "repost" ? "repostCount" : "quoteCount";
  await db.collection("posts").doc(post.sourcePostID).set({
    [field]: FieldValue.increment(amount),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

async function markPostTopicsCounted(postRef: DocumentReference, post: PostRecord) {
  if (!isCountableTopicPost(post)) {
    return;
  }

  await adjustTopicCounts(post.topics ?? [], 1, post.createdAt);
  await postRef.set({ topicCounted: true }, { merge: true });
}

async function syncPostTopicCounts(postID: string, before: PostRecord, after: PostRecord) {
  const beforeCounted = before.topicCounted === true && isCountableTopicPost(before);
  const afterCountable = isCountableTopicPost(after);
  const postRef = db.collection("posts").doc(postID);

  if (beforeCounted && !afterCountable) {
    await adjustTopicCounts(before.topics ?? [], -1);
    if (after.topicCounted === true) {
      await postRef.set({ topicCounted: false }, { merge: true });
    }
    return;
  }

  if (beforeCounted && afterCountable) {
    const beforeTopics = new Set(before.topics ?? []);
    const afterTopics = new Set(after.topics ?? []);
    const added = [...afterTopics].filter((topic) => !beforeTopics.has(topic));
    const removed = [...beforeTopics].filter((topic) => !afterTopics.has(topic));
    if (removed.length > 0) {
      await adjustTopicCounts(removed, -1);
    }
    if (added.length > 0) {
      await adjustTopicCounts(added, 1, after.createdAt);
    }
    return;
  }

  if (!beforeCounted && afterCountable && after.topicCounted !== true) {
    await adjustTopicCounts(after.topics ?? [], 1, after.createdAt);
    await postRef.set({ topicCounted: true }, { merge: true });
  }
}

function isCountableTopicPost(post: PostRecord): boolean {
  return post.isDeleted !== true
    && (post.moderationStatus ?? "active") === "active"
    && Array.isArray(post.topics)
    && post.topics.some(isValidTopic);
}

async function adjustTopicCounts(topics: string[], amount: 1 | -1, lastPostAt?: Timestamp) {
  const uniqueTopics = [...new Set(topics.filter(isValidTopic))];
  for (const topic of uniqueTopics) {
    await adjustTopicRoomPostCount(topic, amount, lastPostAt);
  }
}

async function adjustTopicRoomPostCount(topic: string, amount: 1 | -1, lastPostAt?: Timestamp) {
  const ref = db.collection("topicRooms").doc(topic);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    const currentCount = typeof data?.postCount === "number" ? data.postCount : 0;
    const nextCount = Math.max(currentCount + amount, 0);
    const roomData: Record<string, unknown> = {
      topic,
      title: typeof data?.title === "string" && data.title.length > 0 ? data.title : `#${topic}`,
      description: typeof data?.description === "string" ? data.description : "",
      postCount: nextCount,
      followerCount: typeof data?.followerCount === "number" ? data.followerCount : 0,
      isOfficial: typeof data?.isOfficial === "boolean" ? data.isOfficial : isOfficialTopic(topic),
      moderationStatus: typeof data?.moderationStatus === "string" ? data.moderationStatus : "active",
      updatedAt: FieldValue.serverTimestamp()
    };
    if (!snapshot.exists) {
      roomData.createdAt = FieldValue.serverTimestamp();
    }
    if (amount > 0) {
      roomData.lastPostAt = lastPostAt ?? FieldValue.serverTimestamp();
    } else if (!data?.lastPostAt) {
      roomData.lastPostAt = FieldValue.serverTimestamp();
    }
    transaction.set(ref, roomData, { merge: true });
  });
}

async function adjustTopicFollowerCount(topic: string, amount: 1 | -1) {
  const ref = db.collection("topicRooms").doc(topic);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const data = snapshot.data();
    const currentCount = typeof data?.followerCount === "number" ? data.followerCount : 0;
    const roomData: Record<string, unknown> = {
      topic,
      title: typeof data?.title === "string" && data.title.length > 0 ? data.title : `#${topic}`,
      description: typeof data?.description === "string" ? data.description : "",
      postCount: typeof data?.postCount === "number" ? data.postCount : 0,
      followerCount: Math.max(currentCount + amount, 0),
      isOfficial: typeof data?.isOfficial === "boolean" ? data.isOfficial : isOfficialTopic(topic),
      moderationStatus: typeof data?.moderationStatus === "string" ? data.moderationStatus : "active",
      updatedAt: FieldValue.serverTimestamp()
    };
    if (!snapshot.exists) {
      roomData.createdAt = FieldValue.serverTimestamp();
      roomData.lastPostAt = null;
    }
    transaction.set(ref, roomData, { merge: true });
  });
}

function isValidTopic(topic: unknown): topic is string {
  return typeof topic === "string" && topic.length > 0 && topic.length <= 32 && !topic.includes("/");
}

function isOfficialTopic(topic: string): boolean {
  return ["言葉", "日常ログ", "創作", "学び"].includes(topic);
}

async function canCreateComment(comment: CommentRecord, post: PostRecord): Promise<boolean> {
  if (!post.userID || post.isDeleted === true || (post.moderationStatus ?? "active") !== "active") {
    return false;
  }

  const permission = post.commentPermission ?? "everyone";
  if (permission === "everyone") {
    return true;
  }
  if (permission === "closed") {
    return false;
  }
  if (post.userID === comment.userID) {
    return true;
  }

  const followSnapshot = await db.collection("follows").doc(`${post.userID}_${comment.userID}`).get();
  return followSnapshot.exists;
}

function isCountableComment(comment: CommentRecord): boolean {
  return comment.isDeleted !== true && (comment.moderationStatus ?? "active") === "active";
}

async function adjustCommentCount(postID: string, amount: -1 | 1) {
  const postRef = db.collection("posts").doc(postID);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(postRef);
    const current = snapshot.get("commentCount");
    const currentCount = typeof current === "number" ? current : 0;
    transaction.set(postRef, {
      commentCount: Math.max(currentCount + amount, 0),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  });
}

async function updateFollowCounts(followerID: string, followeeID: string, amount: 1 | -1) {
  const batch = db.batch();
  batch.set(db.collection("users").doc(followerID), {
    followingCount: FieldValue.increment(amount),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
  batch.set(db.collection("users").doc(followeeID), {
    followerCount: FieldValue.increment(amount),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
  await batch.commit();
}

async function isUserActive(userID: string): Promise<boolean> {
  const snapshot = await db.collection("users").doc(userID).get();
  const user = snapshot.data();
  return !!user && user.isDeleted !== true && user.isSuspended !== true;
}

async function exceedsRecentCount(
  collectionName: string,
  userField: string,
  userID: string,
  limit: number
): Promise<boolean> {
  const since = Timestamp.fromMillis(Date.now() - RATE_LIMIT_WINDOW_MS);
  const snapshot = await db.collection(collectionName)
    .where(userField, "==", userID)
    .where("createdAt", ">=", since)
    .limit(limit + 1)
    .get();
  return snapshot.size > limit;
}

async function hideDocument(ref: DocumentReference, reason: string) {
  await ref.set({
    moderationStatus: "hidden",
    hiddenReason: reason,
    hiddenAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

async function renderPostPage(postID: string, baseURL: string, response: PublicPageResponse) {
  if (!postID) {
    response.status(404).send(renderNotFound(baseURL));
    return;
  }

  const postSnapshot = await db.collection("posts").doc(postID).get();
  const post = postSnapshot.data() as PostRecord | undefined;
  if (!post || post.isDeleted === true || (post.moderationStatus ?? "active") !== "active") {
    response.status(404).send(renderNotFound(baseURL));
    return;
  }

  const userSnapshot = await db.collection("users").doc(post.userID).get();
  const user = userSnapshot.data();
  const authorName = typeof user?.displayName === "string" ? user.displayName : "HitoLog";
  const description = truncate(post.body ?? "", 120) || `${authorName}さんのHitoLog投稿`;
  const imageURL = post.mediaItems?.find((item) => item.type === "image" && typeof item.downloadURL === "string")?.downloadURL;
  const canonicalURL = `${baseURL}/p/${encodeURIComponent(postID)}`;
  const topics = (post.topics ?? []).filter(isValidTopic).map((topic) => `<a href="/t/${encodeURIComponent(topic)}">#${escapeHTML(topic)}</a>`).join(" ");
  const createdAt = post.createdAt?.toDate().toLocaleString("ja-JP") ?? "";

  response
    .status(200)
    .set("Cache-Control", "public, max-age=120, s-maxage=300")
    .send(renderBaseHTML({
      title: `${authorName} on HitoLog`,
      description,
      canonicalURL,
      imageURL,
      body: `
        <main>
          <p class="kicker">HitoLog Post</p>
          <h1>${escapeHTML(authorName)}さんの投稿</h1>
          <article class="card">
            <p class="body">${escapeHTML(post.body ?? "").replace(/\n/g, "<br>")}</p>
            ${topics ? `<p class="topics">${topics}</p>` : ""}
            ${createdAt ? `<p class="meta">${escapeHTML(createdAt)}</p>` : ""}
          </article>
          <a class="button" href="/">HitoLogを開く</a>
        </main>`
    }));
}

async function renderTopicPage(topic: string, baseURL: string, response: PublicPageResponse) {
  if (!isValidTopic(topic)) {
    response.status(404).send(renderNotFound(baseURL));
    return;
  }

  const [roomSnapshot, postsSnapshot] = await Promise.all([
    db.collection("topicRooms").doc(topic).get(),
    db.collection("posts")
      .where("topics", "array-contains", topic)
      .where("isDeleted", "==", false)
      .orderBy("createdAt", "desc")
      .limit(5)
      .get()
  ]);
  const room = roomSnapshot.data();
  const title = typeof room?.title === "string" && room.title.length > 0 ? room.title : `#${topic}`;
  const description = typeof room?.description === "string" && room.description.length > 0
    ? room.description
    : `#${topic} の投稿が集まるHitoLogの小部屋です。`;
  const canonicalURL = `${baseURL}/t/${encodeURIComponent(topic)}`;
  const postItems = postsSnapshot.docs
    .map((doc) => doc.data() as PostRecord)
    .filter((post) => post.isDeleted !== true && (post.moderationStatus ?? "active") === "active")
    .map((post) => `<li>${escapeHTML(truncate(post.body ?? "", 90))}</li>`)
    .join("");

  response
    .status(200)
    .set("Cache-Control", "public, max-age=120, s-maxage=300")
    .send(renderBaseHTML({
      title: `${title} | HitoLog`,
      description,
      canonicalURL,
      body: `
        <main>
          <p class="kicker">Topic Room</p>
          <h1>${escapeHTML(title)}</h1>
          <p class="lead">${escapeHTML(description)}</p>
          <p class="meta">${Number(room?.postCount ?? 0)}件の投稿 ・ ${Number(room?.followerCount ?? 0)}人がフォロー</p>
          <section class="card">
            <h2>最近の投稿</h2>
            ${postItems ? `<ul>${postItems}</ul>` : "<p>このルームの投稿はまだありません。</p>"}
          </section>
          <a class="button" href="/">HitoLogを開く</a>
        </main>`
    }));
}

function renderNotFound(baseURL: string): string {
  return renderBaseHTML({
    title: "ページが見つかりません | HitoLog",
    description: "HitoLogのページが見つかりません。",
    canonicalURL: baseURL,
    body: "<main><h1>ページが見つかりません</h1><p>投稿またはルームが削除された可能性があります。</p></main>"
  });
}

function renderBaseHTML(input: {
  title: string;
  description: string;
  canonicalURL: string;
  body: string;
  imageURL?: string;
}): string {
  const imageMeta = input.imageURL ? `
    <meta property="og:image" content="${escapeAttribute(input.imageURL)}">
    <meta name="twitter:image" content="${escapeAttribute(input.imageURL)}">` : "";
  return `<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHTML(input.title)}</title>
  <meta name="description" content="${escapeAttribute(input.description)}">
  <link rel="canonical" href="${escapeAttribute(input.canonicalURL)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="HitoLog">
  <meta property="og:title" content="${escapeAttribute(input.title)}">
  <meta property="og:description" content="${escapeAttribute(input.description)}">
  <meta property="og:url" content="${escapeAttribute(input.canonicalURL)}">
  <meta name="twitter:card" content="${input.imageURL ? "summary_large_image" : "summary"}">
  ${imageMeta}
  <style>
    :root{color-scheme:light;--ink:#1e2421;--muted:#67736d;--paper:#fbfaf6;--line:#ded8cc;--accent:#2f7d5c}
    body{margin:0;background:var(--paper);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"Hiragino Sans","Noto Sans JP",sans-serif;line-height:1.7}
    main{max-width:720px;margin:0 auto;padding:48px 20px}
    h1{font-size:clamp(2rem,6vw,3.6rem);line-height:1.15;margin:8px 0 18px}
    h2{font-size:1.1rem;margin:0 0 12px}
    .kicker{font-size:.8rem;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.08em}
    .lead,.meta{color:var(--muted)}
    .card{border:1px solid var(--line);border-radius:8px;background:#fff;padding:20px;margin:20px 0}
    .body{font-size:1.1rem;white-space:normal}
    .topics a{color:var(--accent);font-weight:700;text-decoration:none;margin-right:8px}
    .button{display:inline-block;background:var(--accent);color:#fff;text-decoration:none;border-radius:8px;padding:10px 14px;font-weight:700}
  </style>
</head>
<body>${input.body}</body>
</html>`;
}

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function escapeAttribute(value: string): string {
  return escapeHTML(value).replace(/\n/g, " ");
}

function truncate(value: string, maxLength: number): string {
  const trimmed = value.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return `${trimmed.slice(0, maxLength - 1)}…`;
}

function notificationTextFor(type: NotificationType, actorName: string): string {
  switch (type) {
    case "comment":
      return `${actorName}さんがコメントしました`;
    case "like":
      return `${actorName}さんがいいねしました`;
    case "follow":
      return `${actorName}さんにフォローされました`;
    case "repost":
      return `${actorName}さんがリポストしました`;
    case "quote":
      return `${actorName}さんが引用しました`;
  }
}
