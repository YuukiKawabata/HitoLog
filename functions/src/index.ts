import { initializeApp } from "firebase-admin/app";
import { DocumentReference, FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
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
  moderationStatus?: ModerationStatus;
  shareType?: PostShareType;
  sourcePostID?: string;
  sourceUserID?: string;
  isDeleted?: boolean;
  commentPermission?: CommentPermission;
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
});

export const onPostUpdated = onDocumentUpdated("posts/{postID}", async (event) => {
  const before = event.data?.before.data() as PostRecord | undefined;
  const after = event.data?.after.data() as PostRecord | undefined;
  if (!before || !after || before.isDeleted === true || after.isDeleted !== true) {
    return;
  }

  await updateShareCount(after, -1);
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
