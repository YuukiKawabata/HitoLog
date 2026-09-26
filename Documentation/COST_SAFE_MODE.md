# 低コスト保管モード

Wamori（旧 HitoLog、App ID 6772677155）は App Store に公開したまま、積極的には伸ばさない「保管」扱いにしている。
目標は次の2点。

1. 放置しても、月額の請求が0円か無料枠の範囲に収まること
2. 攻撃や不具合があっても、請求が上限を超えて増えない構造になっていること（フェイルクローズ）

- 根拠: `/Users/yuki/dev/BILLING_RISK_AUDIT_2026-08-27.md`（HitoLog — High）
- 開始日: 2026-09-26
- このファイルは `docs/` ではなく `Documentation/` に置く（`docs/` は Firebase Hosting で公開されるため）。

## 開始時点の状態（2026-09-26 確認）

| 項目 | 状態 |
|---|---|
| App Store 公開版 | 2.0（2026-09-21 公開）。90日の新規DLは7件 |
| Firebase プロジェクト | `hitolog-e22d2`（Blaze、請求アカウント `01B1AB-F4E762-468956`。kokoro-no-yohaku-jp と共有） |
| Functions | 46個（すべて asia-northeast1）。インスタンス上限は、20が20個、1が2個、未設定（既定で最大100）が24個 |
| スケジュール | 4ジョブ（5分ごと: `processCircleOperationJobs`、毎日: `sendDailyDigest`・`expireCreatorMemberships`・`cleanupCircleEphemeralRecords`）。無料枠は請求アカウント全体で3ジョブ（kokoro 側は0ジョブ） |
| Firestore（直近30日） | 読み取り421件、書き込み22件、削除2件 |
| Storage | `hitolog-e22d2.firebasestorage.app`（US-EAST1、無料枠の対象）に 30.9MB。すべて旧SNSの `postMedia`。輪の画像（`circleMedia`）は0件 |
| Storage 転送（直近30日） | 約157KB |
| Artifact Registry | `gcf-artifacts` 110MB（無料枠0.5GB）。7日で自動削除するポリシーあり |
| 関数の呼び出し（直近30日） | ほぼスケジュール実行のみ。旧SNSの `onPostCreated` は90日で1回 |
| App Check | 輪の callable と購入の callable では強制済み。Firestore・Auth は未強制、Storage は未設定。SDK（App Attest）は初版から入っている |
| GCP 予算 | `Firebase Project hitolog-e22d2`（予算ID `b5054d1f-f243-494e-ad2a-79f435f5996c`）1,000円/月。実績額の 50/90/100% で通知 |
| PostHog | 利用者がオプトインしたときだけ送信（初期値オフ）。画面表示・操作の自動収集とセッションリプレイはオフ |

監査の High 指摘（書き込みから Functions が連鎖する、100MB のメディア、ダイジェストの読み取り増幅）は、いずれも旧SNS（みんなの投稿）側の問題。
2.0 の「輪」は、App Check 付きの callable、書き込み前のレート制限、10MB の JPEG 1枚、削除時の後片付けジョブで守られている。

## 実施内容

### 1. Cloud Functions（`functions/src/`）

| 変更 | 内容 | 目的 |
|---|---|---|
| インスタンス上限 | 全関数に `maxInstances` を設定。callable・HTTP・Firestore トリガーは **3**、スケジュール関数は **1** | 攻撃を受けても、請求が増えるペースを抑える |
| ダイジェストの休止 | `sendDailyDigest` は、`WAMORI_DAILY_DIGEST_ENABLED=true` のときだけ送る。**未設定なら何もせずに終わる**（フェイルクローズ） | 毎晩の通知の読み取り増幅を止める |
| ダイジェストの読み取り上限 | 再開したときの読み取り件数を 5,000 → **500** にする | 再開後も増幅を抑える |

- `circles.ts` は `index.ts` の `setGlobalOptions` より先に評価されるため、`callableOptions` と `publicCircleInvitePreview` に明示的に `maxInstances` を書いている。
- `functions/test/cost-safe-mode.test.cjs` で、ビルドしたマニフェストの全関数に上限があること、スケジュール関数が1であること、ダイジェストが既定で止まることを確認している。
- 利用者への影響: 毎晩19時の「あなたの言葉にN件の反応が届いています」通知が止まる。輪のリアルタイム通知（`enable_circle_push`）は続く。

### 2. 旧SNS（みんなの投稿）を読み取り専用にする

| 変更 | 内容 |
|---|---|
| `firestore.rules` | スイッチ関数 `legacySocialWritesEnabled()` を `false` にした。posts・comments・likes・reactions・follows・topicFollows・articles の作成と編集を拒否する（どれも Functions のトリガーが付いているコレクション） |
| 許可したままの操作 | 閲覧、いいね・フォロー・リアクションの解除（削除）、投稿・記事・コメントの論理削除、プロフィール編集、ブロック・ミュート・通報・フィードバック、招待コード |
| `storage.rules` | スイッチ関数 `legacySocialUploadsEnabled()` を `false` にした。`postMedia`（最大100MBの画像・動画）への新規アップロードを拒否する。閲覧と本人による削除はできる |
| Remote Config | `show_legacy_public_timeline` を `false` にした。2.0 の「自分」タブから「みんなの投稿」への入口が消える |

- 輪（2.0 のメイン機能）は影響を受けない。
- `functions/test/legacy-readonly-rules.test.cjs` で、エミュレータを使って、書き込みの拒否、削除の許可、プロフィールの「京都 → 大阪」の保存ができることを確認している（`npm run test:rules`）。
- デプロイ時に、Storage のルールから Firestore を読むための権限（`roles/firebaserules.firestoreServiceAgent`）を Storage のサービスエージェントに付けた。**それまでこの権限がなかったため、本番では輪の画像のルール（メンバー判定）が働かず、アップロードと表示が拒否されていた可能性が高い。**

## 対応していないこと・残っているリスク

- **ダイジェストのインデックス**: `sendDailyDigest` は少なくとも 2026-09-17 から毎日「インデックスが必要」というエラーで失敗していた（通知は送られていなかった）。再開する場合は、先に `notifications` の複合インデックス（`isRead` と `createdAt`）を `firestore.indexes.json` に追加する。

- **スケジュールジョブ4つ目の料金**: 無料枠（3ジョブ）を1つ超えるため、約$0.10/月かかる可能性がある。ジョブをまとめるには既存の関数とジョブを削除する必要があるため、見送った。
- **削除済み投稿の Storage ファイル**: 削除する処理は入れていない（データを削除しない方針）。今は 30.9MB で無料枠内。
- **輪の下書き画像**: 投稿されなかった下書き（10MB 以下の JPEG）が残る。回数の上限を付けるにはアプリの更新が必要。
- **Firestore の上限**: Firestore には請求の上限（hard limit）を付けられない。インスタンス上限、ルール、App Check で抑える。

## 元に戻す・再開する手順

1. 旧SNSを再開する: `firestore.rules` の `legacySocialWritesEnabled()` と `storage.rules` の `legacySocialUploadsEnabled()` を `true` に戻し、`remoteconfig.template.json` の `show_legacy_public_timeline` を `true` にして、`firebase deploy --only firestore:rules,storage,remoteconfig --project hitolog-e22d2` を実行する。
1. ダイジェストを再開する（先に上記のインデックスを追加する）: `functions/.env` に `WAMORI_DAILY_DIGEST_ENABLED=true` を書き、Functions を再デプロイする。
2. Functions を再デプロイする: `firebase deploy --only functions --project hitolog-e22d2`
3. 本格的に再開する場合: インスタンス上限をこのブランチの変更前に戻し（`git revert`）、予算額を見直す。

## 確認日

- 2026-09-26: 現状把握（CLI・Cloud Monitoring）、Functions の変更、単体テスト（12件成功）、エミュレータでのルールと輪の関数のテスト（11件成功）
- 2026-09-26: 本番にデプロイした（ユーザーが実行。functions・firestore:rules・storage・remoteconfig）。全46関数の `maxScale` が 3（スケジュール関数4個は1）になったこと、Remote Config の `show_legacy_public_timeline=false`、Storage サービスエージェントの権限、デプロイ後1時間のエラーログがないことを確認した
