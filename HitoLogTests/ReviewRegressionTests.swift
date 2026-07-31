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
