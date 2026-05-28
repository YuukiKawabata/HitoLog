# HitoLog

AI時代に、人間の言葉を残すSNS。

HitoLog is an iOS native SNS focused on posts that are typed in the app instead of pasted or mass-generated.

## Source

The initial project follows the Obsidian spec:

`個人/開発/Mobile/Hitolog/hitolog_spec_design_v3.md`

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

## Backend Policy

The app uses Firebase Auth, Cloud Firestore, App Check with App Attest, Firebase Cloud Messaging, Cloud Functions, and PostHog. Local seed and screenshot demo data are development-only aids and are not written to Firebase. Set `POSTHOG_PROJECT_TOKEN` in the Xcode build settings to enable PostHog event delivery.

## Build

Open `HitoLog.xcodeproj` in Xcode, or run:

```sh
xcodebuild -project HitoLog.xcodeproj -scheme HitoLog -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/HitoLogDerivedData CODE_SIGNING_ALLOWED=NO build
```

## Public Pages

GitHub Pages files live in `docs/`.

Recommended App Store Connect URLs after enabling GitHub Pages from the `docs` folder:

- Support URL: `https://<github-user>.github.io/<repo-name>/support/`
- Privacy Policy URL: `https://<github-user>.github.io/<repo-name>/privacy/`
- Terms URL: `https://<github-user>.github.io/<repo-name>/terms/`
