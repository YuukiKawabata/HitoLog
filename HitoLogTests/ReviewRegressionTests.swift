import XCTest
@testable import HitoLog

@MainActor
final class ReviewRegressionTests: XCTestCase {
    func testStoreStartsWithoutPreloadedOrPreviousAccountData() {
        let store = AppDataStore()

        XCTAssertEqual(store.currentUser.id, "local-placeholder")
        XCTAssertTrue(store.currentUser.displayName.isEmpty)
        XCTAssertEqual(store.users, [store.currentUser])
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.comments.isEmpty)
        XCTAssertTrue(store.followingUserIDs.isEmpty)
    }

    func testAuthSessionStartsSignedOutWithoutLocalBypass() {
        let session = AuthSessionStore()

        XCTAssertEqual(session.state, .signedOut)
        XCTAssertNil(session.currentUserID)
        XCTAssertNil(session.appleUserID)
    }

    func testBlockingEveryFollowedUserClearsBothCountAndList() {
        let store = AppDataStore()
        let targetUsers = (1...3).map { makeUser(id: "target-\($0)") }
        store.installUsersForTesting(targetUsers)
        let targetIDs = targetUsers.map(\.id)

        targetIDs.forEach { store.toggleFollow(userID: $0) }
        XCTAssertEqual(store.followingCount(for: store.currentUser.id), 3)

        targetIDs.forEach { store.block($0) }

        XCTAssertEqual(store.followingCount(for: store.currentUser.id), 0)
        XCTAssertTrue(store.following(for: store.currentUser.id).isEmpty)
    }

    func testFailedProfilePersistenceDoesNotChangePublishedProfile() async {
        struct ExpectedFailure: Error {}

        let store = AppDataStore()
        let originalUser = store.currentUser

        do {
            try await store.updateCurrentUser(
                displayName: "変更後",
                handle: originalUser.handle,
                bio: originalUser.bio,
                location: "大阪",
                persistenceOverride: { _ in throw ExpectedFailure() }
            )
            XCTFail("Profile update should throw when persistence fails")
        } catch is ExpectedFailure {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(store.currentUser, originalUser)
        XCTAssertEqual(store.user(for: originalUser.id), originalUser)
    }

    func testSuccessfulProfilePersistencePublishesTheSavedProfile() async throws {
        let store = AppDataStore()
        let originalHandle = store.currentUser.handle

        try await store.updateCurrentUser(
            displayName: "変更後",
            handle: originalHandle,
            bio: store.currentUser.bio,
            location: "大阪",
            persistenceOverride: { _ in }
        )

        XCTAssertEqual(store.currentUser.displayName, "変更後")
        XCTAssertEqual(store.currentUser.location, "大阪")
        XCTAssertEqual(store.user(for: store.currentUser.id), store.currentUser)
    }

    func testClearingLocalSessionRemovesPublishedAccountState() async throws {
        let store = AppDataStore()
        try await store.updateCurrentUser(
            displayName: "端末上のユーザー",
            handle: store.currentUser.handle,
            bio: "端末上のプロフィール",
            location: "大阪",
            persistenceOverride: { _ in }
        )

        store.clearLocalSession()

        XCTAssertEqual(store.currentUser.id, "local-placeholder")
        XCTAssertTrue(store.currentUser.displayName.isEmpty)
        XCTAssertNil(store.currentUser.location)
        XCTAssertEqual(store.users, [store.currentUser])
        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertTrue(store.comments.isEmpty)
    }

    func testLegacyUserDecodesWithoutTimeZoneIdentifier() throws {
        let source = makeUser(id: "legacy-user")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        object.removeValue(forKey: "timeZoneIdentifier")

        let decoded = try JSONDecoder().decode(AppUser.self, from: JSONSerialization.data(withJSONObject: object))

        XCTAssertNil(decoded.timeZoneIdentifier)
    }

    func testCircleInviteRouterSupportsNewLegacyAndUniversalLinks() {
        let router = CircleInviteRouter()
        let token = String(repeating: "a", count: 43)

        XCTAssertEqual(router.route(for: URL(string: "wamori://invite?token=\(token)")!), .invite(token: token))
        XCTAssertEqual(router.route(for: URL(string: "hitolog://invite?token=\(token)")!), .invite(token: token))
        XCTAssertEqual(router.route(for: URL(string: "https://wamori.app/c/\(token)")!), .invite(token: token))
        XCTAssertEqual(router.route(for: URL(string: "https://hitolog-e22d2.web.app/c/\(token)")!), .invite(token: token))
        XCTAssertEqual(CreatedCircleInvite(id: "invite", token: token, expiresAt: Date()).shareURL?.host, "hitolog-e22d2.web.app")
    }

    func testCircleEntryDraftBoundariesAndPhotoOnly() {
        XCTAssertTrue(CircleEntryDraftValidator.isValid(body: String(repeating: "あ", count: 500), hasMedia: false))
        XCTAssertFalse(CircleEntryDraftValidator.isValid(body: String(repeating: "あ", count: 501), hasMedia: false))
        XCTAssertTrue(CircleEntryDraftValidator.isValid(body: "", hasMedia: true))
        XCTAssertFalse(CircleEntryDraftValidator.isValid(body: "  \n", hasMedia: false))
    }

    func testCircleDateKeyUsesProvidedTimeZoneAtDayBoundary() {
        let date = Date(timeIntervalSince1970: 1_735_689_000) // 2025-01-01 JST / 2024-12-31 UTC
        XCTAssertEqual(CircleDataStore.dateKey(for: date, timeZone: TimeZone(identifier: "Asia/Tokyo")!), "2025-01-01")
        XCTAssertEqual(CircleDataStore.dateKey(for: date, timeZone: TimeZone(secondsFromGMT: 0)!), "2024-12-31")
    }

    func testCircleFeatureFlagsStartConservativelyDisabled() {
        let flags = FeatureFlagService.shared

        XCTAssertFalse(flags.enableCircles)
        XCTAssertFalse(flags.circlesAsDefaultHome)
        XCTAssertFalse(flags.enableCircleImages)
        XCTAssertFalse(flags.enableCircleComments)
        XCTAssertFalse(flags.enableCircleReactions)
        XCTAssertFalse(flags.enableCirclePush)
        XCTAssertFalse(flags.enableCircleMoments)
        XCTAssertTrue(flags.showLegacyPublicTimeline)
    }

    func testAnalyticsDropsPrivateCircleProperties() {
        let sanitized = AnalyticsService.shared.privacySafeProperties([
            "entry_point": "write_tab",
            "user_id": "private-user",
            "author_id": "private-author",
            "ownerID": "private-owner",
            "circle_id": "private-circle",
            "circleID": "private-circle-camelcase",
            "circle_name": "family",
            "body": "private entry",
            "comment_text": "private comment",
            "invite_token": "secret",
            "storage_path": "circleMedia/private"
        ])

        XCTAssertEqual(sanitized.count, 1)
        XCTAssertEqual(sanitized["entry_point"] as? String, "write_tab")
    }

    private func makeUser(id: String) -> AppUser {
        let now = Date()
        return AppUser(
            id: id,
            displayName: id,
            handle: id.replacingOccurrences(of: "-", with: "_"),
            bio: "",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 1,
            humanVerifiedPostRate: 0,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
    }
}
