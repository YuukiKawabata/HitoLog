import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";

initializeApp();
setGlobalOptions({ region: "asia-northeast1" });

const db = getFirestore();

type NotificationType = "comment" | "like";

interface PostRecord {
  userID: string;
  body?: string;
}

interface CommentRecord {
  postID: string;
  userID: string;
  body: string;
}

interface LikeRecord {
  postID: string;
  userID: string;
}

export const onCommentCreated = onDocumentCreated("comments/{commentID}", async (event) => {
  const comment = event.data?.data() as CommentRecord | undefined;
  if (!comment) {
    return;
  }

  const postRef = db.collection("posts").doc(comment.postID);
  const postSnapshot = await postRef.get();
  const post = postSnapshot.data() as PostRecord | undefined;
  if (!post) {
    logger.warn("Comment created for missing post", { commentID: event.params.commentID, postID: comment.postID });
    return;
  }

  await postRef.update({
    commentCount: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp()
  });

  await createAndSendNotification({
    type: "comment",
    recipientID: post.userID,
    actorID: comment.userID,
    postID: comment.postID,
    body: comment.body
  });
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

async function createAndSendNotification(input: {
  type: NotificationType;
  recipientID: string;
  actorID: string;
  postID: string;
  body?: string;
}) {
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
  if (!recipient || recipient.notificationsEnabled === false || recipient.isDeleted === true) {
    return;
  }

  if (blockSnapshot.exists || muteSnapshot.exists) {
    return;
  }

  const actor = actorSnapshot.data();
  const actorName = typeof actor?.displayName === "string" ? actor.displayName : "HitoLog";
  const notificationText = input.type === "comment"
    ? `${actorName}さんがコメントしました`
    : `${actorName}さんがいいねしました`;

  await db.collection("notifications").add({
    type: input.type,
    recipientID: input.recipientID,
    actorID: input.actorID,
    postID: input.postID,
    text: notificationText,
    isRead: false,
    createdAt: FieldValue.serverTimestamp()
  });

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

  await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "HitoLog",
      body: notificationText
    },
    data: {
      type: input.type,
      postID: input.postID,
      actorID: input.actorID
    },
    apns: {
      payload: {
        aps: {
          sound: "default"
        }
      }
    }
  });
}
