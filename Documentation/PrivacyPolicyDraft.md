# Wamori Privacy Policy Draft

Wamori handles the information needed to provide accounts, private invitation-only Circles, existing public posts, safety controls, notifications, and product improvement.

## Information collected

- Account identifiers from Sign in with Apple and Firebase Auth.
- Profile information entered by the user.
- Circle membership and invitation state; private entries, images, reactions, and comments.
- Existing public posts, comments, likes, blocks, mutes, and reports.
- Typing-derived input signals such as input duration and edit count.
- Firebase Cloud Messaging tokens when notifications are enabled.
- Feedback and opt-in usage analytics. Entry text, comment text, Circle names, Firebase user/Circle IDs, invitation tokens, and Storage paths are not included in analytics or operational logs.

Raw Circle invitation tokens are returned once when created and are not stored; only a SHA-256 hash is retained for validation. Circle content and images can be read only by active members of that Circle.

## Services and deletion

Wamori uses Firebase Auth, Cloud Firestore, Cloud Storage, Remote Config, App Check, Cloud Messaging, Cloud Functions, and opt-in PostHog analytics. Collected data is not sold.

Users can disable notifications and analytics in Settings. Account deletion removes or hides account and content data. Leaving or removal revokes Circle access immediately, followed by retryable asynchronous cleanup. Reports may be retained when required for safety or legal compliance.

## Contact

- Support: https://wamori.app/support/
- Privacy Policy: https://wamori.app/privacy/
