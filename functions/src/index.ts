import { initializeApp } from "firebase-admin/app";
import { DocumentData, DocumentReference, FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";

initializeApp();
setGlobalOptions({ region: "asia-northeast1" });

const db = getFirestore();

type NotificationType = "comment" | "like" | "follow" | "repost" | "quote" | "mention";
type ModerationStatus = "active" | "reviewRequired" | "hidden";
type PostShareType = "original" | "repost" | "quote";
type CommentPermission = "everyone" | "following" | "closed";

const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000;
const POST_LIMIT_PER_HOUR = 20;
const COMMENT_LIMIT_PER_HOUR = 80;
const FOLLOW_LIMIT_PER_HOUR = 120;
const ESTIMATED_APPLE_COMMISSION_RATE_PERMILLE = 300;
const PLATFORM_FEE_RATE_PERMILLE = 100;
const PAYOUT_HOLD_DAYS = 45;
const MONETIZATION_POLICY_VERSION = "2026-06-v1";

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
  // Human Score 関連（クライアントが自己申告するが、サーバーで再計算して上書きする）
  humanScore?: number;
  humanBadge?: HumanBadge;
  inputDurationMs?: number;
  characterCount?: number;
  editCount?: number;
  deleteCount?: number;
  suspiciousBulkInputCount?: number;
  appCheckVerified?: boolean;
  aiAssisted?: boolean;
}

type HumanBadge = "verified" | "checking" | "lowTrust";

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

interface ReactionRecord {
  postID: string;
  userID: string;
  kind: string;
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

interface ArticleUnlockRecord {
  userID: string;
  articleID: string;
  price?: string;
  transactionID?: string;
  productID?: string;
  counted?: boolean;
}

interface CreatorMembershipRecord {
  subscriberID: string;
  creatorID: string;
  monthlyYen?: number;
  productID?: string;
  latestTransactionID?: string;
  status?: string;
}

interface SupportRecord {
  senderID: string;
  recipientID: string;
  targetType?: string;
  targetID?: string;
  amountYen?: number;
  transactionID?: string;
  productID?: string;
}

interface InviteCodeRecord {
  code: string;
  inviterID: string;
  maxUses?: number;
  useCount?: number;
  isActive?: boolean;
  expiresAt?: Timestamp;
}

interface InviteRedemptionRecord {
  code: string;
  inviteeID: string;
}

interface PublicPageResponse {
  status(code: number): PublicPageResponse;
  set(field: string, value: string): PublicPageResponse;
  send(body: string): void;
}

function articlePriceYen(price?: string): number {
  switch (price) {
    case "yen100": return 100;
    case "yen300": return 300;
    case "yen500": return 500;
    case "yen800": return 800;
    case "yen1000": return 1000;
    default: return 0;
  }
}

function monetizationBreakdown(grossYen: number) {
  const safeGrossYen = Math.max(Math.floor(grossYen), 0);
  const estimatedAppleFeeYen =
    Math.floor(safeGrossYen * ESTIMATED_APPLE_COMMISSION_RATE_PERMILLE / 1000);
  const estimatedAppStoreProceedsYen = Math.max(safeGrossYen - estimatedAppleFeeYen, 0);
  const platformFeeYen =
    Math.floor(estimatedAppStoreProceedsYen * PLATFORM_FEE_RATE_PERMILLE / 1000);
  const creatorPayoutYen = Math.max(estimatedAppStoreProceedsYen - platformFeeYen, 0);

  return {
    grossYen: safeGrossYen,
    estimatedAppleFeeYen,
    estimatedAppStoreProceedsYen,
    platformFeeYen,
    creatorPayoutYen
  };
}

async function createCreatorRevenueEvent(params: {
  eventID: string;
  creatorID: string;
  payerID: string;
  sourceType: "article" | "membership" | "support";
  sourceID: string;
  transactionID: string;
  productID?: string;
  grossYen: number;
  targetType?: string;
  targetID?: string;
}) {
  if (!params.creatorID || !params.payerID || params.creatorID === params.payerID || !params.transactionID) {
    return;
  }

  const breakdown = monetizationBreakdown(params.grossYen);
  if (breakdown.grossYen <= 0) {
    return;
  }

  const payoutEligibleAt = Timestamp.fromMillis(Date.now() + PAYOUT_HOLD_DAYS * 24 * 60 * 60 * 1000);
  const revenueRef = db.collection("creatorRevenueEvents").doc(params.eventID);
  const existing = await revenueRef.get();
  if (existing.exists) {
    return;
  }

  const data: DocumentData = {
    creatorID: params.creatorID,
    payerID: params.payerID,
    sourceType: params.sourceType,
    sourceID: params.sourceID,
    transactionID: params.transactionID,
    grossYen: breakdown.grossYen,
    estimatedAppleCommissionRatePermille: ESTIMATED_APPLE_COMMISSION_RATE_PERMILLE,
    estimatedAppleFeeYen: breakdown.estimatedAppleFeeYen,
    estimatedAppStoreProceedsYen: breakdown.estimatedAppStoreProceedsYen,
    platformFeeRatePermille: PLATFORM_FEE_RATE_PERMILLE,
    platformFeeYen: breakdown.platformFeeYen,
    creatorPayoutYen: breakdown.creatorPayoutYen,
    payoutStatus: "pending",
    payoutEligibleAt,
    monetizationPolicyVersion: MONETIZATION_POLICY_VERSION,
    createdAt: FieldValue.serverTimestamp()
  };

  if (params.productID) {
    data.productID = params.productID;
  }
  if (params.targetType) {
    data.targetType = params.targetType;
  }
  if (params.targetID) {
    data.targetID = params.targetID;
  }

  await revenueRef.set(data, { merge: false });
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

  await finalizeHumanScore(postRef, post);
  await handlePostShareCreated(post, event.params.postID);
  await sendMentionNotifications(post, event.params.postID);
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

const REACTION_KINDS = ["empathy", "insight", "cheer"];

function isValidReactionKind(kind: unknown): kind is string {
  return typeof kind === "string" && REACTION_KINDS.includes(kind);
}

async function adjustReactionCount(postID: string, kind: string, amount: 1 | -1) {
  await db.collection("posts").doc(postID).set({
    reactionCounts: { [kind]: FieldValue.increment(amount) },
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });
}

// リアクション付与時に、投稿ドキュメントの reactionCounts.{kind} を集計する。
// 全ユーザーに同じ件数が見えるよう、サーバー側で権威ある集計を保つ。
export const onReactionCreated = onDocumentCreated("reactions/{reactionID}", async (event) => {
  const reaction = event.data?.data() as ReactionRecord | undefined;
  if (!reaction || !reaction.postID || !isValidReactionKind(reaction.kind)) {
    return;
  }

  await adjustReactionCount(reaction.postID, reaction.kind, 1);
});

export const onReactionDeleted = onDocumentDeleted("reactions/{reactionID}", async (event) => {
  const reaction = event.data?.data() as ReactionRecord | undefined;
  if (!reaction || !reaction.postID || !isValidReactionKind(reaction.kind)) {
    return;
  }

  await adjustReactionCount(reaction.postID, reaction.kind, -1);
});

export const onReactionUpdated = onDocumentUpdated("reactions/{reactionID}", async (event) => {
  const before = event.data?.before.data() as ReactionRecord | undefined;
  const after = event.data?.after.data() as ReactionRecord | undefined;
  if (!before || !after || before.postID !== after.postID || before.kind === after.kind) {
    return;
  }

  const reactionCounts: Record<string, FieldValue> = {};
  if (isValidReactionKind(before.kind)) {
    reactionCounts[before.kind] = FieldValue.increment(-1);
  }
  if (isValidReactionKind(after.kind)) {
    reactionCounts[after.kind] = FieldValue.increment(1);
  }
  if (Object.keys(reactionCounts).length > 0) {
    await db.collection("posts").doc(after.postID).set({
      reactionCounts,
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  }
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

export const onArticleUnlockCreated = onDocumentCreated("articleUnlocks/{unlockID}", async (event) => {
  const unlock = event.data?.data() as ArticleUnlockRecord | undefined;
  if (!unlock || !unlock.userID || !unlock.articleID || unlock.counted === true) {
    return;
  }

  const articleRef = db.collection("articles").doc(unlock.articleID);
  const articleSnapshot = await articleRef.get();
  const article = articleSnapshot.data();
  const creatorID = typeof article?.userID === "string" ? article.userID : "";
  const grossYen = articlePriceYen(unlock.price);

  await articleRef.set({
    purchaseCount: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp()
  }, { merge: true });

  if (creatorID && unlock.transactionID && grossYen > 0) {
    await createCreatorRevenueEvent({
      eventID: `article_${unlock.transactionID}`,
      creatorID,
      payerID: unlock.userID,
      sourceType: "article",
      sourceID: unlock.articleID,
      transactionID: unlock.transactionID,
      productID: unlock.productID,
      grossYen
    });
  }

  await db.collection("articleUnlocks").doc(event.params.unlockID).set({
    counted: true
  }, { merge: true });
});

export const onCreatorMembershipCreated = onDocumentCreated("creatorMemberships/{membershipID}", async (event) => {
  const membership = event.data?.data() as CreatorMembershipRecord | undefined;
  if (!membership || membership.status !== "active" || !membership.latestTransactionID) {
    return;
  }

  await createCreatorRevenueEvent({
    eventID: `membership_${membership.latestTransactionID}`,
    creatorID: membership.creatorID,
    payerID: membership.subscriberID,
    sourceType: "membership",
    sourceID: event.params.membershipID,
    transactionID: membership.latestTransactionID,
    productID: membership.productID,
    grossYen: membership.monthlyYen ?? 0
  });
});

export const onCreatorMembershipUpdated = onDocumentUpdated("creatorMemberships/{membershipID}", async (event) => {
  const before = event.data?.before.data() as CreatorMembershipRecord | undefined;
  const after = event.data?.after.data() as CreatorMembershipRecord | undefined;
  if (!after || after.status !== "active" || !after.latestTransactionID) {
    return;
  }
  if (before?.latestTransactionID === after.latestTransactionID) {
    return;
  }

  await createCreatorRevenueEvent({
    eventID: `membership_${after.latestTransactionID}`,
    creatorID: after.creatorID,
    payerID: after.subscriberID,
    sourceType: "membership",
    sourceID: event.params.membershipID,
    transactionID: after.latestTransactionID,
    productID: after.productID,
    grossYen: after.monthlyYen ?? 0
  });
});

export const onSupportCreated = onDocumentCreated("supports/{supportID}", async (event) => {
  const support = event.data?.data() as SupportRecord | undefined;
  if (!support || !support.transactionID) {
    return;
  }

  await createCreatorRevenueEvent({
    eventID: `support_${support.transactionID}`,
    creatorID: support.recipientID,
    payerID: support.senderID,
    sourceType: "support",
    sourceID: event.params.supportID,
    transactionID: support.transactionID,
    productID: support.productID,
    grossYen: support.amountYen ?? 0,
    targetType: support.targetType,
    targetID: support.targetID
  });
});

export const onInviteRedemptionCreated = onDocumentCreated("inviteRedemptions/{redemptionID}", async (event) => {
  const redemption = event.data?.data() as InviteRedemptionRecord | undefined;
  if (!redemption || !redemption.code || !redemption.inviteeID) {
    return;
  }

  const code = normalizeInviteCode(redemption.code);
  if (!code) {
    await db.collection("inviteRedemptions").doc(event.params.redemptionID).set({
      status: "rejected",
      rejectionReason: "invalid_code",
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
    return;
  }
  const redemptionRef = db.collection("inviteRedemptions").doc(event.params.redemptionID);
  const inviteRef = db.collection("inviteCodes").doc(code);
  const inviteeRef = db.collection("users").doc(redemption.inviteeID);

  await db.runTransaction(async (transaction) => {
    const [inviteSnapshot, inviteeSnapshot] = await Promise.all([
      transaction.get(inviteRef),
      transaction.get(inviteeRef)
    ]);
    const invite = inviteSnapshot.data() as InviteCodeRecord | undefined;
    const invitee = inviteeSnapshot.data();

    const rejectionReason = inviteRedemptionRejectionReason(invite, invitee, redemption.inviteeID);
    if (rejectionReason) {
      transaction.set(redemptionRef, {
        code,
        status: "rejected",
        rejectionReason,
        updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
      return;
    }

    const inviterID = invite?.inviterID ?? "";
    transaction.set(inviteRef, {
      useCount: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
    transaction.set(inviteeRef, {
      invitedByUserID: inviterID,
      invitedByInviteCode: code,
      invitedAt: FieldValue.serverTimestamp(),
      humanLevel: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
    transaction.set(db.collection("users").doc(inviterID), {
      humanLevel: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
    transaction.set(redemptionRef, {
      code,
      inviterID,
      status: "accepted",
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  });
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

  if (path.startsWith("/i/")) {
    await renderInvitePage(path.replace("/i/", "").split("/")[0], baseURL, response);
    return;
  }

  if (path.startsWith("/og/post/")) {
    await renderPostOGImage(path.replace("/og/post/", "").split("/")[0], response);
    return;
  }

  response.status(404).send(renderBaseHTML({
    title: "HitoLog",
    description: "HitoLogは、自分の言葉で書くSNSです。",
    canonicalURL: baseURL,
    body: "<main><h1>HitoLog</h1><p>ページが見つかりません。</p></main>"
  }));
});

// ===== 習慣化リエンゲージ通知（1日1回のダイジェスト）=====
//
// フォロー中の新着や自分の投稿への反応を1日分まとめて配信し、毎日開く理由をつくる。
// スパムにならないよう「未読がある人」だけに1日1通。ユーザー設定（notificationsEnabled）で制御。
export const sendDailyDigest = onSchedule(
  { schedule: "0 19 * * *", timeZone: "Asia/Tokyo" },
  async () => {
    const since = Timestamp.fromMillis(Date.now() - 24 * 60 * 60 * 1000);
    const snapshot = await db.collection("notifications")
      .where("createdAt", ">=", since)
      .where("isRead", "==", false)
      .limit(5000)
      .get();

    // 受信者ごとに未読件数を集計する。
    const unreadByRecipient = new Map<string, number>();
    for (const doc of snapshot.docs) {
      const recipientID = doc.data().recipientID;
      if (typeof recipientID === "string") {
        unreadByRecipient.set(recipientID, (unreadByRecipient.get(recipientID) ?? 0) + 1);
      }
    }

    let sentCount = 0;
    for (const [recipientID, count] of unreadByRecipient) {
      const sent = await sendDigestPush(recipientID, count);
      if (sent) {
        sentCount += 1;
      }
    }

    logger.info("Daily digest processed", { recipients: unreadByRecipient.size, sent: sentCount });
  }
);

export const expireCreatorMemberships = onSchedule(
  { schedule: "15 3 * * *", timeZone: "Asia/Tokyo" },
  async () => {
    const now = Timestamp.now();
    const snapshot = await db.collection("creatorMemberships")
      .where("status", "==", "active")
      .where("expiresAt", "<", now)
      .limit(500)
      .get();

    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.set(doc.ref, {
        status: "expired",
        updatedAt: FieldValue.serverTimestamp()
      }, { merge: true });
    }
    await batch.commit();
    logger.info("Expired creator memberships", { count: snapshot.size });
  }
);

async function sendDigestPush(recipientID: string, unreadCount: number): Promise<boolean> {
  const recipientSnapshot = await db.collection("users").doc(recipientID).get();
  const recipient = recipientSnapshot.data();
  if (!recipient || recipient.notificationsEnabled === false || recipient.isDeleted === true || recipient.isSuspended === true) {
    return false;
  }

  const tokenSnapshot = await db.collection("fcmTokens")
    .doc(recipientID)
    .collection("tokens")
    .where("isEnabled", "==", true)
    .get();

  const tokens = tokenSnapshot.docs
    .map((doc) => doc.data().token)
    .filter((token): token is string => typeof token === "string" && token.length > 0);

  if (tokens.length === 0) {
    return false;
  }

  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "HitoLog",
      body: `あなたの言葉に${unreadCount}件の反応が届いています`
    },
    data: { type: "digest" },
    apns: { payload: { aps: { sound: "default" } } }
  });

  return true;
}

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

function normalizeInviteCode(code: string): string {
  return code.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function inviteRedemptionRejectionReason(
  invite: InviteCodeRecord | undefined,
  invitee: DocumentData | undefined,
  inviteeID: string
): string | null {
  if (!invite || !invite.inviterID || normalizeInviteCode(invite.code ?? "") === "") {
    return "missing_invite";
  }
  if (invite.isActive === false) {
    return "inactive_invite";
  }
  if (invite.inviterID === inviteeID) {
    return "self_invite";
  }
  if (!invitee || invitee.isDeleted === true || invitee.isSuspended === true) {
    return "inactive_invitee";
  }
  if (typeof invitee.invitedByUserID === "string" && invitee.invitedByUserID.length > 0) {
    return "already_redeemed";
  }
  const maxUses = typeof invite.maxUses === "number" ? invite.maxUses : 5;
  const useCount = typeof invite.useCount === "number" ? invite.useCount : 0;
  if (useCount >= maxUses) {
    return "invite_exhausted";
  }
  if (invite.expiresAt instanceof Timestamp && invite.expiresAt.toMillis() < Date.now()) {
    return "invite_expired";
  }
  return null;
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
  const canonicalURL = `${baseURL}/p/${encodeURIComponent(postID)}`;
  const imageURL = `${baseURL}/og/post/${encodeURIComponent(postID)}`;
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

async function renderInvitePage(rawCode: string, baseURL: string, response: PublicPageResponse) {
  const code = normalizeInviteCode(rawCode);
  if (!code) {
    response.status(404).send(renderNotFound(baseURL));
    return;
  }

  const inviteSnapshot = await db.collection("inviteCodes").doc(code).get();
  const invite = inviteSnapshot.data() as InviteCodeRecord | undefined;
  const inviterSnapshot = invite?.inviterID ? await db.collection("users").doc(invite.inviterID).get() : undefined;
  const inviter = inviterSnapshot?.data();
  const inviterName = typeof inviter?.displayName === "string" ? inviter.displayName : "HitoLog";
  const remainingUses = Math.max((invite?.maxUses ?? 5) - (invite?.useCount ?? 0), 0);
  const isAvailable = !!invite && invite.isActive !== false && remainingUses > 0
    && (!(invite.expiresAt instanceof Timestamp) || invite.expiresAt.toMillis() >= Date.now());
  const canonicalURL = `${baseURL}/i/${encodeURIComponent(code)}`;
  const appURL = `hitolog://invite?code=${encodeURIComponent(code)}`;

  response
    .status(200)
    .set("Cache-Control", "public, max-age=60, s-maxage=120")
    .send(renderBaseHTML({
      title: "HitoLogへの招待",
      description: `${inviterName}さんからHitoLogへの招待です。`,
      canonicalURL,
      body: `
        <main>
          <p class="kicker">Invitation</p>
          <h1>HitoLogへの招待</h1>
          <p class="lead">${escapeHTML(inviterName)}さんから招待が届いています。</p>
          <section class="card">
            <p class="meta">招待コード</p>
            <p class="code">${escapeHTML(code)}</p>
            <p>${isAvailable ? `残り${remainingUses}回使えます。` : "この招待コードは利用できません。"}</p>
          </section>
          <a class="button" href="${escapeAttribute(appURL)}">HitoLogで受け取る</a>
        </main>`
    }));
}

async function renderPostOGImage(postID: string, response: PublicPageResponse) {
  const postSnapshot = await db.collection("posts").doc(postID).get();
  const post = postSnapshot.data() as PostRecord | undefined;
  if (!post || post.isDeleted === true || (post.moderationStatus ?? "active") !== "active") {
    response.status(404).send("");
    return;
  }

  const userSnapshot = await db.collection("users").doc(post.userID).get();
  const user = userSnapshot.data();
  const authorName = typeof user?.displayName === "string" ? user.displayName : "HitoLog";
  const handle = typeof user?.handle === "string" ? `@${user.handle}` : "@hitolog";
  const bodyLines = svgTextLines(post.body ?? "", 34, 5);
  const badgeLabel = humanBadgeOGLabel(post.humanBadge);
  const badgeColor = post.humanBadge === "verified" ? "#2f7d5c" : post.humanBadge === "lowTrust" ? "#8a6a32" : "#67736d";

  response
    .status(200)
    .set("Content-Type", "image/svg+xml; charset=utf-8")
    .set("Cache-Control", "public, max-age=120, s-maxage=300")
    .send(`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <rect width="1200" height="630" fill="#fbfaf6"/>
  <rect x="56" y="56" width="1088" height="518" rx="28" fill="#ffffff" stroke="#ded8cc" stroke-width="2"/>
  <text x="96" y="124" fill="#2f7d5c" font-family="-apple-system,BlinkMacSystemFont,'Hiragino Sans','Noto Sans JP',sans-serif" font-size="28" font-weight="700">HitoLog</text>
  <rect x="94" y="154" width="${Math.max(220, badgeLabel.length * 28)}" height="52" rx="26" fill="${badgeColor}" opacity="0.12"/>
  <text x="122" y="188" fill="${badgeColor}" font-family="-apple-system,BlinkMacSystemFont,'Hiragino Sans','Noto Sans JP',sans-serif" font-size="25" font-weight="700">${escapeHTML(badgeLabel)}</text>
  ${bodyLines.map((line, index) => `<text x="96" y="${276 + index * 58}" fill="#1e2421" font-family="-apple-system,BlinkMacSystemFont,'Hiragino Sans','Noto Sans JP',sans-serif" font-size="38" font-weight="650">${escapeHTML(line)}</text>`).join("\n  ")}
  <text x="96" y="522" fill="#67736d" font-family="-apple-system,BlinkMacSystemFont,'Hiragino Sans','Noto Sans JP',sans-serif" font-size="26">${escapeHTML(authorName)} ${escapeHTML(handle)}</text>
  <text x="868" y="522" fill="#67736d" font-family="-apple-system,BlinkMacSystemFont,'Hiragino Sans','Noto Sans JP',sans-serif" font-size="24">AI時代に、人間の言葉を残すSNS。</text>
</svg>`);
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
    .code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:1.6rem;font-weight:800;letter-spacing:.04em;margin:.2rem 0}
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

function svgTextLines(value: string, maxCharsPerLine: number, maxLines: number): string[] {
  const compact = value.replace(/\s+/g, " ").trim();
  if (!compact) {
    return ["人間の言葉を、HitoLogに。"];
  }

  const lines: string[] = [];
  let cursor = 0;
  while (cursor < compact.length && lines.length < maxLines) {
    const next = compact.slice(cursor, cursor + maxCharsPerLine);
    cursor += maxCharsPerLine;
    lines.push(cursor < compact.length && lines.length === maxLines - 1 ? `${next.slice(0, -1)}…` : next);
  }
  return lines;
}

function humanBadgeOGLabel(badge: HumanBadge | undefined): string {
  switch (badge) {
    case "verified":
      return "本人入力 verified";
    case "lowTrust":
      return "入力確認中";
    default:
      return "Human Score 確認中";
  }
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
    case "mention":
      return `${actorName}さんがあなたをメンションしました`;
  }
}

// ===== @メンション =====

const MAX_MENTIONS_PER_POST = 10;
const MAX_HANDLE_LENGTH = 32;

// 本文から @handle を正規化抽出する。HitoLog/Core/Models/Post.swift の MentionExtractor と一致させる。
function extractHandles(body: string): string[] {
  const seen = new Set<string>();
  const result: string[] = [];

  for (const token of body.split(/\s+/)) {
    if (token[0] !== "@" && token[0] !== "＠") {
      continue;
    }
    const match = token.slice(1).match(/^[A-Za-z0-9_]+/);
    if (!match) {
      continue;
    }
    const handle = match[0].toLowerCase().slice(0, MAX_HANDLE_LENGTH);
    if (handle.length < 2 || seen.has(handle)) {
      continue;
    }
    seen.add(handle);
    result.push(handle);
    if (result.length >= MAX_MENTIONS_PER_POST) {
      break;
    }
  }

  return result;
}

async function sendMentionNotifications(post: PostRecord, postID: string): Promise<void> {
  if (post.shareType === "repost" || !post.body) {
    return;
  }

  const handles = extractHandles(post.body);
  if (handles.length === 0) {
    return;
  }

  const notifiedUserIDs = new Set<string>();
  for (const handle of handles) {
    const userSnapshot = await db.collection("users")
      .where("handleLowercase", "==", handle)
      .limit(1)
      .get();
    const mentionedUser = userSnapshot.docs[0];
    if (!mentionedUser) {
      continue;
    }

    const recipientID = mentionedUser.id;
    // 自分自身・重複・共有元（quote の通知と重複）への二重通知を避ける。
    if (recipientID === post.userID || notifiedUserIDs.has(recipientID) || recipientID === post.sourceUserID) {
      continue;
    }
    notifiedUserIDs.add(recipientID);

    await createAndSendNotification({
      type: "mention",
      recipientID,
      actorID: post.userID,
      postID,
      body: post.body
    });
  }

  if (notifiedUserIDs.size > 0) {
    logger.info("Mention notifications sent", { postID, count: notifiedUserIDs.size });
  }
}

// ===== Human Score（サーバー側で確定。クライアントの自己申告を信用しない）=====
//
// HitoLog の核となる「人間が、考えて書いた」価値の土台。クライアントが humanScore を
// 100 と偽って書き込んでも、サーバーが入力計測値から再計算して上書きするため改ざんできない。
// 算定ロジックは HitoLog/Core/Services/HumanScoreService.swift と一致させること。

interface HumanScoreInput {
  inputDurationMs: number;
  characterCount: number;
  editCount: number;
  deleteCount: number;
  suspiciousBulkInputCount: number;
  appAttestVerified: boolean;
  accountAgeDays: number;
  recentPostCount: number;
  aiAssisted: boolean;
}

function computeHumanScore(input: HumanScoreInput): number {
  let score = 100;

  if (!input.appAttestVerified) {
    score -= 20;
  }

  // 一括入力（ペースト/AI生成貼り付け）の疑い。ただし正直に「AI併用」を
  // 開示している場合は、欺瞞ではないためペナルティを科さない。
  if (input.suspiciousBulkInputCount > 0 && !input.aiAssisted) {
    score -= 30 * input.suspiciousBulkInputCount;
  }

  const seconds = Math.max(input.inputDurationMs / 1000, 1);
  const charsPerSecond = input.characterCount / seconds;

  if (input.characterCount >= 100 && charsPerSecond > 10) {
    score -= 20;
  }

  if (input.recentPostCount >= 10) {
    score -= 10;
  }

  if (input.accountAgeDays < 1) {
    score -= 5;
  }

  if (input.editCount > 0 || input.deleteCount > 0) {
    score += 5;
  }

  return Math.min(Math.max(score, 0), 100);
}

function humanBadgeForScore(score: number): HumanBadge {
  if (score >= 80) {
    return "verified";
  } else if (score >= 50) {
    return "checking";
  }
  return "lowTrust";
}

function toFiniteNumber(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function accountAgeDaysFrom(createdAt: unknown): number {
  if (createdAt instanceof Timestamp) {
    const ageMs = Date.now() - createdAt.toMillis();
    return Math.max(Math.floor(ageMs / (24 * 60 * 60 * 1000)), 0);
  }
  return 0;
}

// 直近1時間の自分の投稿数。recentPostCount として Human Score の権威ある入力に使う。
async function recentPostCountFor(userID: string): Promise<number> {
  const since = Timestamp.fromMillis(Date.now() - RATE_LIMIT_WINDOW_MS);
  const snapshot = await db.collection("posts")
    .where("userID", "==", userID)
    .where("createdAt", ">=", since)
    .limit(POST_LIMIT_PER_HOUR + 1)
    .get();
  return snapshot.size;
}

// 投稿の Human Score をサーバー側で再計算し、自己申告と異なれば上書きする。
// リポストは本文を持たないため対象外（共有元の値を引き継ぐ）。
async function finalizeHumanScore(postRef: DocumentReference, post: PostRecord): Promise<void> {
  if (post.shareType === "repost") {
    return;
  }

  const authorSnapshot = await db.collection("users").doc(post.userID).get();
  const accountAgeDays = accountAgeDaysFrom(authorSnapshot.data()?.createdAt);

  const computedScore = computeHumanScore({
    inputDurationMs: toFiniteNumber(post.inputDurationMs),
    characterCount: toFiniteNumber(post.characterCount, (post.body ?? "").length),
    editCount: toFiniteNumber(post.editCount),
    deleteCount: toFiniteNumber(post.deleteCount),
    suspiciousBulkInputCount: toFiniteNumber(post.suspiciousBulkInputCount),
    appAttestVerified: post.appCheckVerified === true,
    accountAgeDays,
    recentPostCount: await recentPostCountFor(post.userID),
    aiAssisted: post.aiAssisted === true,
  });
  const computedBadge = humanBadgeForScore(computedScore);

  if (computedScore !== post.humanScore || computedBadge !== post.humanBadge) {
    await postRef.set({
      humanScore: computedScore,
      humanBadge: computedBadge,
      updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });
  }
}
