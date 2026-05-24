# HitoLog TestFlight Review Notes

## App Summary
HitoLog is a social posting app focused on writing text directly in the app. The compose screen blocks paste input and records typing signals such as duration, edit count, delete count, and suspicious bulk input count to show a Human Check badge.

## Sign-In
Use Sign in with Apple. Firebase Auth stores the authenticated user ID and profile document.

## Firebase Data
- `users/{uid}`: profile, Apple user ID, notification preference.
- `posts/{postID}`: post body, author ID, human score signals, like/comment counts.
- `comments/{commentID}`: comment body, post ID, author ID, human score.
- `likes/{postID}_{uid}`: one like per user per post.
- `blocks/{blockerID}_{blockedUserID}` and `mutes/{muterID}_{mutedUserID}`: safety preferences.
- `reports/{reportID}`: user-submitted reports.
- `fcmTokens/{uid}/tokens/{tokenID}`: iOS FCM token records for push notifications.

## Push Notifications
The app asks for notification permission from Settings. Cloud Functions send FCM notifications for comments and likes. Notifications are skipped for self-actions, notification-off recipients, and blocked or muted actor relationships.

## Reviewer Path
1. Sign in with Apple.
2. Complete onboarding.
3. Create a post from the 投稿 tab.
4. Open a post and add a comment.
5. Like and unlike a post.
6. Open Settings to edit profile, change notification preference, and inspect block/mute/report screens.

## Required Console Setup Before Submission
- Add the real `GoogleService-Info.plist` to `HitoLog/Resources/` and to the Xcode target resources.
- Enable Firebase Auth Sign in with Apple, Firestore, Cloud Messaging, and App Check.
- Upload the APNs Auth Key to Firebase Cloud Messaging.
- Confirm the Apple App ID has Sign in with Apple, Push Notifications, and App Attest capabilities.
- Deploy Firestore rules, indexes, and Cloud Functions.
