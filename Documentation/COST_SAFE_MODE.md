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

### 2-1. アプリ 2.0.1（ビルド13、コミット `7edf893`）

ルールで旧SNSの書き込みを止めただけでは、2.0 のアプリで次の2つの問題が残るため、アプリも更新した。

| 変更 | 内容 | 理由 |
|---|---|---|
| `FeatureFlagService` の既定値 | 公開中の Remote Config に合わせた（輪の各フラグをオン、`show_legacy_public_timeline=false`、`legacy_social_writes_enabled=false`） | 2.0 の既定値は「輪オフ・旧SNSを表示」だった。初回起動やオフラインで Remote Config を取得できないと、閲覧のみの旧SNSが表示されてしまう |
| `AppDataStore` | 旧SNSの作成・編集（投稿・コメント・いいね・リアクション・フォロー・話題フォロー・記事）を `allowsLegacySocialWrite()` で止め、ルート画面に「みんなの投稿は閲覧のみです」のアラートを出す。解除（いいね・フォローの取り消しなど）と削除はできる | 2.0 では画面上は先に反映され（楽観的更新）、ルールに拒否されて保存されないため、利用者から見ると「消える」不具合になる |

- 旧SNSを再開するときは、ルールのスイッチ（下の「元に戻す・再開する手順」）に加えて、Remote Config に `legacy_social_writes_enabled=true` を追加する。これがないと 2.0.1 以降のアプリは書き込まない。
- 2026-09-28 23:13（JST）に審査へ提出した。提出時に「概要評価をリセット」を選んだ（2.0 以前の星の平均と件数が消える。レビュー本文は残る。元に戻せない）。★2レビュー（2026-07-09）には返信していない。
- 提出の流れ: `fastlane submit_review`（`fastlane/Fastfile`）でバージョン 2.0.1 を作り、新機能の文章を登録した → API でビルド13を割り当てた → 「概要評価をリセット」と「審査へ提出」は、ユーザーが App Store Connect の画面で行った。App Store Connect API には評価リセットの窓口（`resetRatingsRequests`）がなく、fastlane の `reset_ratings` は API キーでは失敗するため（fastlane/fastlane#21328）。
- 署名: `fastlane beta` はこのとき署名エラーで失敗した。Xcode 管理の App Store 用プロファイルに、キーチェーンにある Apple Distribution 証明書（`NM4KKMKRHY`、2026-09-23 作成）が入っておらず、API キーにはクラウド署名の権限がないため自動更新もできなかった。手動のプロファイル「Wamori App Store (manual) 20260928」（`A53U7PQHQA`）を作り、アーカイブを手動署名で書き出して `xcrun altool` でアップロードした。また、シェルのロケールが UTF-8 でないと fastlane と xcpretty が日本語の出力で止まった。
- 2026-09-28 に `fastlane/Fastfile` を直した。`build` レーン（アップロードしない）で上の手動プロファイルを読み取り専用で取得し（`readonly: true`。Portal 側は変更しない）、手動署名で書き出す。`beta` はこれを呼んでからアップロードする。ファイルの先頭で UTF-8 を強制している。LANG なしのシェルで `fastlane ios build` が成功し、IPA が Apple Distribution で署名されることを確認した。
- 手動プロファイルの期限は Apple Distribution 証明書と同じ 2027-09-23。証明書を作り直したときは、プロファイルも作り直して Fastfile の `provisioning_name` を合わせる。

### 2-2. App Check と PostHog（2026-09-28）

- **Firestore の App Check を強制した**（Firebase コンソール）。直前の7日間は 834件中834件（100%）が検証済みで、未検証は0件だった。
- **Storage の App Check も強制した**（ユーザーの判断）。コンソールに指標が出ておらず（直近7日間のリクエストがない）、検証済みの割合は確認できなかった。アプリには初版から App Check が入っており、Firestore で 100% 検証済みのため、同じ仕組みで Storage のリクエストにもトークンが付く想定。旧SNSや輪の画像が表示されないという報告があれば、まずこれを疑い、コンソールの「適用解除」で戻す。
- Authentication（プレビュー）は 100% 検証済みで、モニタリングのまま。
- **PostHog**（US、組織「HitoLog」）は無料プランで、カードは未登録。各製品の Billing limit は無料枠と同じ値で、請求は発生しない。

### 3. GCP 予算（2026-09-26 変更済み）

- 対象の予算: `Firebase Project hitolog-e22d2`（請求アカウント `01B1AB-F4E762-468956`、予算ID `b5054d1f-f243-494e-ad2a-79f435f5996c`）
- 変更前: 1,000円/月、実績額の 50% / 90% / 100% で通知
- 変更後: **300円/月**、実績額の 50% / 90% / 100% と、**予測額の 100%** で通知
- 予算は通知だけで、請求そのものは止まらない。請求を止める仕組みは、Functions のインスタンス上限とルールが担う。

## 対応していないこと・残っているリスク

- **ダイジェストのインデックス**: `sendDailyDigest` は少なくとも 2026-09-17 から毎日「インデックスが必要」というエラーで失敗していた（通知は送られていなかった）。再開する場合は、先に `notifications` の複合インデックス（`isRead` と `createdAt`）を `firestore.indexes.json` に追加する。

- **スケジュールジョブ4つ目の料金**: 無料枠（3ジョブ）を1つ超えるため、約$0.10/月かかる可能性がある。ジョブをまとめるには既存の関数とジョブを削除する必要があるため、見送った。
- **削除済み投稿の Storage ファイル**: 削除する処理は入れていない（データを削除しない方針）。今は 30.9MB で無料枠内。
- **輪の下書き画像**: 投稿されなかった下書き（10MB 以下の JPEG）が残る。回数の上限を付けるにはアプリの更新が必要。
- **Firestore の上限**: Firestore には請求の上限（hard limit）を付けられない。インスタンス上限、ルール、App Check で抑える。

## 元に戻す・再開する手順

1. 旧SNSを再開する: `firestore.rules` の `legacySocialWritesEnabled()` と `storage.rules` の `legacySocialUploadsEnabled()` を `true` に戻し、`remoteconfig.template.json` の `show_legacy_public_timeline` を `true` にし、`legacy_social_writes_enabled=true` を追加して（2.0.1 以降のアプリはこれがないと書き込まない）、`firebase deploy --only firestore:rules,storage,remoteconfig --project hitolog-e22d2` を実行する。
1. ダイジェストを再開する（先に上記のインデックスを追加する）: `functions/.env` に `WAMORI_DAILY_DIGEST_ENABLED=true` を書き、Functions を再デプロイする。
2. Functions を再デプロイする: `firebase deploy --only functions --project hitolog-e22d2`
3. 本格的に再開する場合: インスタンス上限をこのブランチの変更前に戻し（`git revert`）、予算額を見直す（`gcloud billing budgets update b5054d1f-f243-494e-ad2a-79f435f5996c --billing-account=01B1AB-F4E762-468956 --budget-amount=<額>JPY`）。

## 確認日

- 2026-09-26: 現状把握（CLI・Cloud Monitoring）、Functions の変更、単体テスト（12件成功）、エミュレータでのルールと輪の関数のテスト（11件成功）
- 2026-09-26: 本番にデプロイした（ユーザーが実行。functions・firestore:rules・storage・remoteconfig）。全46関数の `maxScale` が 3（スケジュール関数4個は1）になったこと、Remote Config の `show_legacy_public_timeline=false`、Storage サービスエージェントの権限、デプロイ後1時間のエラーログがないことを確認した
- 2026-09-26: GCP 予算を 300円/月に変更し、予測額の100%通知を追加した（ユーザーが実行、反映を確認）
- 2026-09-28: 2.0.1（ビルド13）をアップロードし（処理結果 VALID）、概要評価をリセットして審査に提出した。API で `appStoreState=WAITING_FOR_REVIEW` を確認した
- 2026-09-28: Firestore（直前7日間の検証率 100%）と Storage（指標なし）の App Check を強制し、両方「適用済み」を確認した。PostHog が無料プランでカード未登録であることを確認した
