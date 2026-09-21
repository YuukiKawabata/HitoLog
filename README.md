# Wamori 2.0

大切な人と、今日をひとつずつ。

Wamori is an invitation-only social journal for circles of two to five close people. It is delivered as the 2.0 update of the existing HitoLog app, preserving the bundle ID, target, Firebase project, products, and public-post data.

## Source

The initial project follows the Obsidian spec:

`個人/開発/モバイル/HitoLog/hitolog_spec_design_v3.md`

## Stack

- iOS
- Swift
- SwiftUI
- UIKit `UITextView` for no-paste input
- Firebase-backed data store with local seed data for development and previews.

## Current Scope

- Native SwiftUI app skeleton
- TabView based navigation
- Timeline UI with like and comment flows
- Compose tab and post submission animation
- NoPasteTextView
- Typing metrics
- Human Score
- Initial login and onboarding
- Profile editing
- Block, mute, report history, logout, and account deletion flows
- In-app feedback submission and StoreKit review prompts from Settings and positive usage milestones
- PostHog-backed usage analytics with an in-app opt-out toggle
- Sign in with Apple through Firebase Auth
- Firestore sync for profiles, posts, comments, likes, safety settings, reports, and push tokens
- Firebase Cloud Messaging notifications for comments and likes
- Private Circle data, invitations, daily entries, one-photo uploads, reactions, comments, ownership transfer, and asynchronous cleanup
- Firebase Remote Config rollout switches with conservative defaults

## Backend Policy

The app uses Firebase Auth, Cloud Firestore, App Check with App Attest, Firebase Cloud Messaging, Cloud Functions, and PostHog. Runtime content is loaded from the authenticated user's production Firebase data. Set `POSTHOG_PROJECT_TOKEN` in the Xcode build settings to enable PostHog event delivery.

## Build

Open `HitoLog.xcodeproj` in Xcode, or run:

```sh
xcodebuild -project HitoLog.xcodeproj -scheme HitoLog -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/HitoLogDerivedData CODE_SIGNING_ALLOWED=NO build
```

## Public Pages

GitHub Pages files live in `docs/`.

Canonical URLs after connecting the custom domain:

- Support URL: `https://wamori.app/support/`
- Privacy Policy URL: `https://wamori.app/privacy/`
- Terms URL: `https://wamori.app/terms/`

Until `wamori.app` is acquired and connected, production invitations, support, privacy, and App Store metadata use `https://hitolog-e22d2.web.app`. Both hosts and both `wamori://` / `hitolog://` schemes remain supported, so the later switch is backward-compatible.
