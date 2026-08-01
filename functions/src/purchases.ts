import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  Environment,
  JWSTransactionDecodedPayload,
  SignedDataVerifier,
  Type,
  VerificationException,
  VerificationStatus
} from "@apple/app-store-server-library";
import { Firestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

const APP_BUNDLE_ID = "com.yukikawabata.HitoLog";
const APP_APPLE_ID = 6772677155;
const PURCHASE_INTENT_VALIDITY_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_SIGNED_TRANSACTION_LENGTH = 20_000;

type ProductKind = "article" | "membership" | "support";

interface ProductDefinition {
  kind: ProductKind;
  value: string;
  grossYen: number;
  appleType: Type;
}

const PRODUCTS: Readonly<Record<string, ProductDefinition>> = {
  "jp.hitolog.article_unlock_100": {
    kind: "article", value: "yen100", grossYen: 100, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.article_unlock_300": {
    kind: "article", value: "yen300", grossYen: 300, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.article_unlock_500": {
    kind: "article", value: "yen500", grossYen: 500, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.article_unlock_800": {
    kind: "article", value: "yen800", grossYen: 800, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.article_unlock_1000": {
    kind: "article", value: "yen1000", grossYen: 1000, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.creator_membership.v2.monthly_300": {
    kind: "membership", value: "monthly300", grossYen: 300,
    appleType: Type.AUTO_RENEWABLE_SUBSCRIPTION
  },
  "jp.hitolog.creator_membership.v3.monthly_500": {
    kind: "membership", value: "monthly500", grossYen: 500,
    appleType: Type.AUTO_RENEWABLE_SUBSCRIPTION
  },
  "jp.hitolog.creator_membership.v3.monthly_1000": {
    kind: "membership", value: "monthly1000", grossYen: 1000,
    appleType: Type.AUTO_RENEWABLE_SUBSCRIPTION
  },
  "jp.hitolog.support.once_100": {
    kind: "support", value: "yen100", grossYen: 100, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.support.once_300": {
    kind: "support", value: "yen300", grossYen: 300, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.support.once_500": {
    kind: "support", value: "yen500", grossYen: 500, appleType: Type.CONSUMABLE
  },
  "jp.hitolog.support.once_1000": {
    kind: "support", value: "yen1000", grossYen: 1000, appleType: Type.CONSUMABLE
  }
};

export type PurchasePurpose =
  | { kind: "article"; articleID: string }
  | { kind: "membership"; creatorID: string }
  | {
      kind: "support";
      recipientID: string;
      targetType: "profile" | "post" | "article";
      targetID?: string;
    };

interface PurchaseIntentRecord {
  userID: string;
  productID: string;
  productKind: ProductKind;
  value: string;
  grossYen: number;
  purpose: PurchasePurpose;
  status: "pending" | "consumed";
  consumedTransactionID?: string;
}

interface CompletionResult {
  transactionID: string;
  productID: string;
  kind: ProductKind;
  expirationDate: number | null;
  alreadyCompleted: boolean;
}

function authenticatedUID(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "サインインが必要です。");
  }
  return uid;
}

function requiredString(value: unknown, field: string, maximumLength = 128): string {
  if (typeof value !== "string" || value.length === 0 || value.length > maximumLength) {
    throw new HttpsError("invalid-argument", `${field}が不正です。`);
  }
  return value;
}

function documentID(value: unknown, field: string): string {
  const result = requiredString(value, field);
  if (result.includes("/")) {
    throw new HttpsError("invalid-argument", `${field}が不正です。`);
  }
  return result;
}

export function productDefinition(productID: string): Readonly<ProductDefinition> | undefined {
  return PRODUCTS[productID];
}

export function parsePurchasePurpose(value: unknown): PurchasePurpose {
  if (!value || typeof value !== "object") {
    throw new HttpsError("invalid-argument", "購入対象が不正です。");
  }
  const raw = value as Record<string, unknown>;
  switch (raw.kind) {
    case "article":
      return { kind: "article", articleID: documentID(raw.articleID, "articleID") };
    case "membership":
      return { kind: "membership", creatorID: documentID(raw.creatorID, "creatorID") };
    case "support": {
      const recipientID = documentID(raw.recipientID, "recipientID");
      if (raw.targetType !== "profile" && raw.targetType !== "post" && raw.targetType !== "article") {
        throw new HttpsError("invalid-argument", "targetTypeが不正です。");
      }
      const targetID = raw.targetID === undefined || raw.targetID === null || raw.targetID === ""
        ? undefined
        : documentID(raw.targetID, "targetID");
      if (raw.targetType === "profile" && targetID !== undefined) {
        throw new HttpsError("invalid-argument", "プロフィール支援にtargetIDは指定できません。");
      }
      if (raw.targetType !== "profile" && targetID === undefined) {
        throw new HttpsError("invalid-argument", "支援対象のIDが必要です。");
      }
      return { kind: "support", recipientID, targetType: raw.targetType, ...(targetID ? { targetID } : {}) };
    }
    default:
      throw new HttpsError("invalid-argument", "購入対象の種類が不正です。");
  }
}

async function ensureActiveUser(db: Firestore, userID: string): Promise<void> {
  const snapshot = await db.collection("users").doc(userID).get();
  const user = snapshot.data();
  if (!snapshot.exists || user?.isDeleted === true || user?.isSuspended === true) {
    throw new HttpsError("failed-precondition", "対象のユーザーは現在利用できません。");
  }
}

async function validatePurposeBeforePurchase(
  db: Firestore,
  uid: string,
  product: ProductDefinition,
  purpose: PurchasePurpose
): Promise<void> {
  if (product.kind !== purpose.kind) {
    throw new HttpsError("invalid-argument", "商品と購入対象が一致しません。");
  }

  if (purpose.kind === "article") {
    const article = await db.collection("articles").doc(purpose.articleID).get();
    const data = article.data();
    if (!article.exists || data?.status !== "published" || data?.isDeleted === true) {
      throw new HttpsError("not-found", "購入対象の記事が見つかりません。");
    }
    if (data?.userID === uid) {
      throw new HttpsError("failed-precondition", "自分の記事は購入できません。");
    }
    if (data?.price !== product.value) {
      throw new HttpsError("failed-precondition", "記事価格が更新されています。画面を再読み込みしてください。");
    }
    const existingUnlock = await db.collection("articleUnlocks").doc(`${uid}_${purpose.articleID}`).get();
    if (existingUnlock.exists) {
      throw new HttpsError("already-exists", "この記事は購入済みです。");
    }
    return;
  }

  if (purpose.kind === "membership") {
    if (purpose.creatorID === uid) {
      throw new HttpsError("failed-precondition", "自分のメンバーシップは購入できません。");
    }
    await ensureActiveUser(db, purpose.creatorID);
    return;
  }

  if (purpose.recipientID === uid) {
    throw new HttpsError("failed-precondition", "自分自身を支援することはできません。");
  }
  await ensureActiveUser(db, purpose.recipientID);

  if (purpose.targetType === "post" && purpose.targetID) {
    const target = await db.collection("posts").doc(purpose.targetID).get();
    if (!target.exists || target.data()?.userID !== purpose.recipientID || target.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "支援対象の投稿が見つかりません。");
    }
  } else if (purpose.targetType === "article" && purpose.targetID) {
    const target = await db.collection("articles").doc(purpose.targetID).get();
    if (!target.exists || target.data()?.userID !== purpose.recipientID || target.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "支援対象の記事が見つかりません。");
    }
  }
}

export function makeCreatePurchaseIntentHandler(db: Firestore) {
  return async (request: CallableRequest<unknown>): Promise<{ intentID: string }> => {
    const uid = authenticatedUID(request);
    if (!request.data || typeof request.data !== "object") {
      throw new HttpsError("invalid-argument", "購入情報が不正です。");
    }
    const input = request.data as Record<string, unknown>;
    const productID = requiredString(input.productID, "productID", 200);
    const product = productDefinition(productID);
    if (!product) {
      throw new HttpsError("invalid-argument", "未登録の商品です。");
    }
    const purpose = parsePurchasePurpose(input.purpose);
    await ensureActiveUser(db, uid);
    await validatePurposeBeforePurchase(db, uid, product, purpose);

    const intentID = randomUUID();
    await db.collection("purchaseIntents").doc(intentID).create({
      userID: uid,
      productID,
      productKind: product.kind,
      value: product.value,
      grossYen: product.grossYen,
      purpose,
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + PURCHASE_INTENT_VALIDITY_MS)
    });
    return { intentID };
  };
}

let rootCertificates: Buffer[] | undefined;
let productionVerifier: SignedDataVerifier | undefined;
let sandboxVerifier: SignedDataVerifier | undefined;

function loadAppleRootCertificates(): Buffer[] {
  if (!rootCertificates) {
    const certificateDirectory = join(__dirname, "..", "certs");
    rootCertificates = [
      "AppleIncRootCertificate.cer.b64",
      "AppleRootCA-G2.cer.b64",
      "AppleRootCA-G3.cer.b64"
    ].map((filename) => Buffer.from(readFileSync(join(certificateDirectory, filename), "utf8").trim(), "base64"));
  }
  return rootCertificates;
}

function environmentFromUntrustedJWS(signedTransaction: string): Environment {
  const parts = signedTransaction.split(".");
  if (parts.length !== 3) {
    throw new HttpsError("invalid-argument", "Apple取引情報の形式が不正です。");
  }
  try {
    const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as Record<string, unknown>;
    if (payload.environment === Environment.PRODUCTION) {
      return Environment.PRODUCTION;
    }
    if (payload.environment === Environment.SANDBOX) {
      return Environment.SANDBOX;
    }
  } catch {
    throw new HttpsError("invalid-argument", "Apple取引情報を読み取れません。");
  }
  throw new HttpsError("invalid-argument", "未対応の購入環境です。");
}

async function verifyAppleTransaction(signedTransaction: string): Promise<JWSTransactionDecodedPayload> {
  const environment = environmentFromUntrustedJWS(signedTransaction);
  try {
    if (environment === Environment.PRODUCTION) {
      productionVerifier ??= new SignedDataVerifier(
        loadAppleRootCertificates(), true, Environment.PRODUCTION, APP_BUNDLE_ID, APP_APPLE_ID
      );
      return await productionVerifier.verifyAndDecodeTransaction(signedTransaction);
    }
    sandboxVerifier ??= new SignedDataVerifier(
      loadAppleRootCertificates(), true, Environment.SANDBOX, APP_BUNDLE_ID
    );
    return await sandboxVerifier.verifyAndDecodeTransaction(signedTransaction);
  } catch (error) {
    logger.error("App Store transaction verification failed", error);
    if (error instanceof VerificationException &&
        error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) {
      throw new HttpsError("unavailable", "Appleで購入を確認できませんでした。自動的に再試行します。");
    }
    throw new HttpsError("permission-denied", "購入の署名を確認できませんでした。");
  }
}

function validateVerifiedTransaction(payload: JWSTransactionDecodedPayload): {
  transactionID: string;
  productID: string;
  intentID: string;
  product: ProductDefinition;
} {
  const transactionID = requiredString(payload.transactionId, "transactionID", 100);
  const productID = requiredString(payload.productId, "productID", 200);
  const intentID = requiredString(payload.appAccountToken, "appAccountToken", 100);
  const product = productDefinition(productID);
  if (!product || payload.type !== product.appleType || payload.quantity !== 1) {
    throw new HttpsError("failed-precondition", "商品情報が登録内容と一致しません。");
  }
  if (payload.revocationDate !== undefined) {
    throw new HttpsError("failed-precondition", "返金または取り消し済みの購入です。");
  }
  if (product.kind === "membership" && typeof payload.expiresDate !== "number") {
    throw new HttpsError("failed-precondition", "メンバーシップの有効期限を確認できません。");
  }
  return { transactionID, productID, intentID, product };
}

function sameUserCompletion(data: FirebaseFirestore.DocumentData | undefined, uid: string): CompletionResult {
  if (!data || data.userID !== uid) {
    throw new HttpsError("permission-denied", "この取引は別のアカウントに登録されています。");
  }
  return {
    transactionID: data.transactionID as string,
    productID: data.productID as string,
    kind: data.productKind as ProductKind,
    expirationDate: data.expirationDate instanceof Timestamp ? data.expirationDate.toMillis() : null,
    alreadyCompleted: true
  };
}

export function makeCompletePurchaseHandler(db: Firestore) {
  return async (request: CallableRequest<unknown>): Promise<CompletionResult> => {
    const uid = authenticatedUID(request);
    if (!request.data || typeof request.data !== "object") {
      throw new HttpsError("invalid-argument", "購入情報が不正です。");
    }
    const signedTransaction = requiredString(
      (request.data as Record<string, unknown>).signedTransaction,
      "signedTransaction",
      MAX_SIGNED_TRANSACTION_LENGTH
    );
    const payload = await verifyAppleTransaction(signedTransaction);
    const { transactionID, productID, intentID, product } = validateVerifiedTransaction(payload);

    return db.runTransaction(async (transaction) => {
      const ledgerRef = db.collection("appStoreTransactions").doc(transactionID);
      const ledgerSnapshot = await transaction.get(ledgerRef);
      if (ledgerSnapshot.exists) {
        return sameUserCompletion(ledgerSnapshot.data(), uid);
      }

      const intentRef = db.collection("purchaseIntents").doc(intentID);
      const intentSnapshot = await transaction.get(intentRef);
      const intent = intentSnapshot.data() as PurchaseIntentRecord | undefined;
      if (!intentSnapshot.exists || !intent) {
        throw new HttpsError("failed-precondition", "購入の事前登録が見つかりません。");
      }
      if (intent.userID !== uid || intent.productID !== productID || intent.productKind !== product.kind) {
        throw new HttpsError("permission-denied", "購入の事前登録とApple取引が一致しません。");
      }
      const isMembershipRenewal = product.kind === "membership" && intent.status === "consumed";
      if (intent.status === "consumed" && !isMembershipRenewal) {
        throw new HttpsError("already-exists", "この購入の事前登録は使用済みです。");
      }

      const purchaseDate = typeof payload.purchaseDate === "number"
        ? Timestamp.fromMillis(payload.purchaseDate)
        : Timestamp.now();
      const expirationDate = typeof payload.expiresDate === "number"
        ? Timestamp.fromMillis(payload.expiresDate)
        : null;
      const commonLedger = {
        transactionID,
        originalTransactionID: payload.originalTransactionId ?? transactionID,
        userID: uid,
        productID,
        productKind: product.kind,
        intentID,
        environment: payload.environment ?? "unknown",
        purchaseDate,
        expirationDate,
        verifiedAt: FieldValue.serverTimestamp()
      };

      if (intent.purpose.kind === "article" && product.kind === "article") {
        const unlockRef = db.collection("articleUnlocks").doc(`${uid}_${intent.purpose.articleID}`);
        transaction.set(unlockRef, {
          userID: uid,
          articleID: intent.purpose.articleID,
          price: product.value,
          transactionID,
          productID,
          purchaseDate,
          createdAt: FieldValue.serverTimestamp()
        }, { merge: false });
      } else if (intent.purpose.kind === "membership" && product.kind === "membership") {
        const membershipRef = db.collection("creatorMemberships")
          .doc(`${uid}_${intent.purpose.creatorID}`);
        transaction.set(membershipRef, {
          subscriberID: uid,
          creatorID: intent.purpose.creatorID,
          plan: product.value,
          monthlyYen: product.grossYen,
          productID,
          latestTransactionID: transactionID,
          status: expirationDate && expirationDate.toMillis() > Date.now() ? "active" : "expired",
          expiresAt: expirationDate,
          updatedAt: FieldValue.serverTimestamp()
        }, { merge: true });
      } else if (intent.purpose.kind === "support" && product.kind === "support") {
        const supportData: FirebaseFirestore.DocumentData = {
          senderID: uid,
          recipientID: intent.purpose.recipientID,
          targetType: intent.purpose.targetType,
          amount: product.value,
          amountYen: product.grossYen,
          transactionID,
          productID,
          purchaseDate,
          createdAt: FieldValue.serverTimestamp()
        };
        if (intent.purpose.targetID) {
          supportData.targetID = intent.purpose.targetID;
        }
        transaction.create(db.collection("supports").doc(transactionID), supportData);
      } else {
        throw new HttpsError("failed-precondition", "購入対象と商品種別が一致しません。");
      }

      transaction.create(ledgerRef, commonLedger);
      transaction.set(intentRef, {
        status: "consumed",
        consumedTransactionID: transactionID,
        consumedAt: FieldValue.serverTimestamp()
      }, { merge: true });

      return {
        transactionID,
        productID,
        kind: product.kind,
        expirationDate: expirationDate?.toMillis() ?? null,
        alreadyCompleted: false
      };
    });
  };
}
