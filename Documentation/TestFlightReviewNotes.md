# Wamori 2.0 TestFlight Review Notes

## App summary

Wamori is the 2.0 update of HitoLog. Existing accounts and public posts remain available. The main experience is an invitation-only “Circle” (Japanese UI: 「輪」) for two to five close people, with one private entry per member and local calendar day.

## Reviewer path

1. Sign in with Apple using a review account.
2. Confirm the one-time “HitoLogはWamoriになりました” migration screen when upgrading a 1.x install.
3. Create a Circle or join from a `https://hitolog-e22d2.web.app/c/{token}` invitation. This is the live compatibility host until `wamori.app` is connected.
4. Use the center Write tab. With one Circle it opens the editor directly; with multiple Circles it asks for a destination.
5. Create a text or one-photo entry, then test reactions and comments from another member.
6. Open Self > Public Posts to confirm the existing public timeline and composer remain available.
7. As owner, inspect invitation revocation, member removal, ownership transfer, and Circle deletion.

## Privacy and security

- Circle reads require an active membership in Firestore and Storage Rules.
- Circle mutations use App Check-enforced callable Functions.
- Invitation tokens contain 256 bits of entropy; only SHA-256 hashes are persisted.
- Push text is generic and does not include Circle names, post text, comment text, identifiers, tokens, or Storage paths.
- Circle media is one JPEG up to 10 MB and 1,600 px on its longest edge.
- Account deletion requires ownership transfer when another active member remains.

## Rollout

The release template enables Circles, default Circle navigation, images, comments, reactions, and generic push notifications. Setting `enable_circles=false` restores the legacy navigation without deleting Circle data.

Production Firebase and Remote Config are deployed. Build 12 is the final TestFlight/App Store candidate. The custom-domain connection remains pending acquisition of `wamori.app`.
