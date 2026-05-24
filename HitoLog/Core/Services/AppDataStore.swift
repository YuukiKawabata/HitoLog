import Combine
import Foundation

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var currentUser: AppUser
    @Published private(set) var users: [AppUser]
    @Published private(set) var posts: [Post]
    @Published private(set) var comments: [Comment]
    @Published private(set) var likedPostIDs: Set<String>
    @Published private(set) var blockedUserIDs: Set<String>
    @Published private(set) var mutedUserIDs: Set<String>
    @Published private(set) var reportHistory: [ReportRecord]
    @Published private(set) var isRemoteSyncEnabled = false
    @Published private(set) var isDemoDataVisible = false
    @Published private(set) var lastSyncErrorMessage: String?

    private let remoteStore: FirebaseDataStore
    private let initialCurrentUser: AppUser
    private let initialUsers: [AppUser]
    private let initialPosts: [Post]
    private let initialComments: [Comment]
    private let initialLikedPostIDs: Set<String>
    private var remoteUserID: String?

    var recentPostCount: Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return posts.filter { $0.userId == currentUser.id && !$0.isDeleted && $0.createdAt >= oneHourAgo }.count
    }

    var verifiedPostRate: Double {
        let visiblePosts = posts.filter { !$0.isDeleted }
        guard !visiblePosts.isEmpty else { return 0 }
        let verifiedCount = visiblePosts.filter { $0.humanBadge == .verified }.count
        return Double(verifiedCount) / Double(visiblePosts.count)
    }

    var timelinePosts: [Post] {
        posts.filter { post in
            !post.isDeleted && !blockedUserIDs.contains(post.userId) && !mutedUserIDs.contains(post.userId)
        }
        .sorted {
            $0.createdAt > $1.createdAt
        }
    }

    var timelineVerifiedPostRate: Double {
        guard !timelinePosts.isEmpty else { return 0 }
        let verifiedCount = timelinePosts.filter { $0.humanBadge == .verified }.count
        return Double(verifiedCount) / Double(timelinePosts.count)
    }

    init(remoteStore: FirebaseDataStore = FirebaseDataStore()) {
        let seed = MockDataStore()
        self.remoteStore = remoteStore
        self.initialCurrentUser = seed.currentUser
        self.initialUsers = seed.users
        self.initialPosts = seed.posts
        self.initialComments = seed.comments
        self.initialLikedPostIDs = seed.likedPostIDs
        self.currentUser = seed.currentUser
        self.users = seed.users
        self.posts = seed.posts
        self.comments = seed.comments
        self.likedPostIDs = seed.likedPostIDs
        self.blockedUserIDs = seed.blockedUserIDs
        self.mutedUserIDs = seed.mutedUserIDs
        self.reportHistory = seed.reportHistory
    }

    func activateRemoteUser(uid: String?, appleUserID: String?, displayName: String?, email: String?) async {
        remoteUserID = uid

        guard let uid, remoteStore.isAvailable else {
            isRemoteSyncEnabled = false
            return
        }

        isRemoteSyncEnabled = true
        lastSyncErrorMessage = nil

        do {
            if let remoteUser = try await remoteStore.loadUser(userID: uid), !remoteUser.isDeleted {
                adoptRemoteUser(remoteUser, appleUserID: appleUserID)
            } else {
                adoptSignedInUser(uid: uid, appleUserID: appleUserID, displayName: displayName)
            }

            try await remoteStore.upsertUser(currentUser, email: email)
            try await reloadRemoteSnapshot()
        } catch {
            recordRemoteError(error)
        }
    }

    func deactivateRemoteUser() {
        remoteUserID = nil
        isRemoteSyncEnabled = false
        lastSyncErrorMessage = nil
    }

    func user(for id: String) -> AppUser? {
        users.first { $0.id == id }
    }

    func post(for id: String) -> Post? {
        posts.first { $0.id == id && !$0.isDeleted }
    }

    func insert(_ post: Post) {
        posts.insert(post, at: 0)
        runRemoteWrite {
            try await self.remoteStore.savePost(post)
        }
    }

    func updatePost(postID: String, body: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              let index = posts.firstIndex(where: { $0.id == postID && $0.userId == currentUser.id && !$0.isDeleted }) else {
            return
        }

        posts[index] = posts[index].replacingBody(trimmedBody)

        guard !postID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.updatePostBody(postID: postID, body: trimmedBody)
        }
    }

    func deletePost(postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID && $0.userId == currentUser.id && !$0.isDeleted }) else {
            return
        }

        posts[index].isDeleted = true
        posts[index].updatedAt = Date()
        likedPostIDs.remove(postID)

        guard !postID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.deletePost(postID: postID)
        }
    }

    func updateCurrentUser(displayName: String, handle: String, bio: String, avatarUrl: String? = nil) async throws {
        currentUser.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.avatarUrl = avatarUrl
        currentUser.updatedAt = Date()

        if let index = users.firstIndex(where: { $0.id == currentUser.id }) {
            users[index] = currentUser
        } else {
            users.insert(currentUser, at: 0)
        }

        let user = currentUser
        guard isRemoteSyncEnabled else { return }

        do {
            try await remoteStore.upsertUser(user, email: nil)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
            throw error
        }
    }

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID && !$0.isDeleted }) else { return }

        let isLiked: Bool
        if likedPostIDs.contains(postID) {
            likedPostIDs.remove(postID)
            posts[index].likeCount = max(posts[index].likeCount - 1, 0)
            isLiked = false
        } else {
            likedPostIDs.insert(postID)
            posts[index].likeCount += 1
            isLiked = true
        }

        guard !postID.hasPrefix("demo-") else { return }
        let userID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setLike(postID: postID, userID: userID, isLiked: isLiked)
        }
    }

    func comments(for postID: String) -> [Comment] {
        comments
            .filter { $0.postId == postID && !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(body: String, to postID: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty, post(for: postID) != nil else { return }

        let now = Date()
        let comment = Comment(
            id: UUID().uuidString,
            postId: postID,
            userId: currentUser.id,
            body: trimmedBody,
            humanScore: 88,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        comments.append(comment)

        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index].commentCount += 1
        }

        guard !postID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.addComment(comment)
        }
    }

    func postCount(for userID: String) -> Int {
        posts.filter { $0.userId == userID && !$0.isDeleted }.count
    }

    func blockedUsers() -> [AppUser] {
        users.filter { blockedUserIDs.contains($0.id) }
    }

    func mutedUsers() -> [AppUser] {
        users.filter { mutedUserIDs.contains($0.id) }
    }

    func block(_ userID: String) {
        guard userID != currentUser.id else { return }
        blockedUserIDs.insert(userID)
        mutedUserIDs.remove(userID)

        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setBlock(blockerID: currentUserID, blockedUserID: userID, isBlocked: true)
            try await self.remoteStore.setMute(muterID: currentUserID, mutedUserID: userID, isMuted: false)
        }
    }

    func unblock(_ userID: String) {
        blockedUserIDs.remove(userID)

        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setBlock(blockerID: currentUserID, blockedUserID: userID, isBlocked: false)
        }
    }

    func mute(_ userID: String) {
        guard userID != currentUser.id else { return }
        mutedUserIDs.insert(userID)

        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setMute(muterID: currentUserID, mutedUserID: userID, isMuted: true)
        }
    }

    func unmute(_ userID: String) {
        mutedUserIDs.remove(userID)

        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setMute(muterID: currentUserID, mutedUserID: userID, isMuted: false)
        }
    }

    func addReport(targetDescription: String, reason: String) {
        let report = ReportRecord(
            id: UUID().uuidString,
            targetDescription: targetDescription,
            reason: reason,
            createdAt: Date(),
            status: "確認待ち"
        )
        reportHistory.insert(report, at: 0)

        let reporterID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.addReport(report, reporterID: reporterID)
        }
    }

    func resetLocalAccount() {
        currentUser = initialCurrentUser
        users = initialUsers
        posts = initialPosts
        comments = initialComments
        likedPostIDs = initialLikedPostIDs
        blockedUserIDs = []
        mutedUserIDs = []
        reportHistory = []
        isDemoDataVisible = false
        deactivateRemoteUser()
    }

    func deleteCurrentAccountData() async throws {
        let userID = currentUser.id

        if isRemoteSyncEnabled {
            do {
                try await remoteStore.deleteAccountData(userID: userID)
                lastSyncErrorMessage = nil
            } catch {
                recordRemoteError(error)
                throw error
            }
        }

        currentUser.isDeleted = true
        if let userIndex = users.firstIndex(where: { $0.id == userID }) {
            users[userIndex] = currentUser
        }

        for index in posts.indices where posts[index].userId == userID {
            posts[index].isDeleted = true
            posts[index].updatedAt = Date()
        }

        for index in comments.indices where comments[index].userId == userID {
            comments[index].isDeleted = true
            comments[index].updatedAt = Date()
        }

        likedPostIDs.removeAll()
        blockedUserIDs.removeAll()
        mutedUserIDs.removeAll()
    }

    func showScreenshotDemoData() {
        isDemoDataVisible = true
        applyScreenshotDemoData()
    }

    func hideScreenshotDemoData() async {
        isDemoDataVisible = false

        if isRemoteSyncEnabled {
            do {
                try await reloadRemoteSnapshot()
            } catch {
                recordRemoteError(error)
            }
        } else {
            users = initialUsers
            posts = initialPosts
            comments = initialComments
            likedPostIDs = initialLikedPostIDs
            blockedUserIDs = []
            mutedUserIDs = []
            reportHistory = []
        }
    }

    func refresh() async {
        guard isRemoteSyncEnabled else {
            try? await Task.sleep(nanoseconds: 250_000_000)
            return
        }

        do {
            try await reloadRemoteSnapshot()
        } catch {
            recordRemoteError(error)
        }
    }

    private func reloadRemoteSnapshot() async throws {
        guard let remoteUserID else { return }
        let snapshot = try await remoteStore.loadSnapshot(currentUserID: remoteUserID)

        if let remoteCurrentUser = snapshot.users.first(where: { $0.id == remoteUserID }) {
            currentUser = remoteCurrentUser
        } else {
            try await remoteStore.upsertUser(currentUser, email: nil)
        }

        users = mergeCurrentUser(into: snapshot.users)
        posts = snapshot.posts
        comments = snapshot.comments
        likedPostIDs = snapshot.likedPostIDs
        blockedUserIDs = snapshot.blockedUserIDs
        mutedUserIDs = snapshot.mutedUserIDs
        reportHistory = snapshot.reports
        if isDemoDataVisible {
            applyScreenshotDemoData()
        }
        lastSyncErrorMessage = nil
    }

    private func applyScreenshotDemoData() {
        let seed = MockDataStore()
        let seedCurrentUserID = seed.currentUser.id
        let demoUsers = seed.users
            .filter { $0.id != seedCurrentUserID && $0.id != currentUser.id }

        users = mergeCurrentUser(into: uniqueUsers(users + demoUsers))
        posts = uniquePosts(posts.filter { !$0.id.hasPrefix("demo-") } + seed.posts.map { post in
            post.demoCopy(currentUserID: currentUser.id, seedCurrentUserID: seedCurrentUserID)
        })
        comments = uniqueComments(comments.filter { !$0.id.hasPrefix("demo-") } + seed.comments.map { comment in
            comment.demoCopy(currentUserID: currentUser.id, seedCurrentUserID: seedCurrentUserID)
        })
        likedPostIDs.formUnion(seed.likedPostIDs.map { "demo-\($0)" })
    }

    private func uniqueUsers(_ users: [AppUser]) -> [AppUser] {
        var seen = Set<String>()
        return users.filter { user in
            guard !seen.contains(user.id), !user.isDeleted else { return false }
            seen.insert(user.id)
            return true
        }
    }

    private func uniquePosts(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts
            .filter { post in
                guard !seen.contains(post.id), !post.isDeleted else { return false }
                seen.insert(post.id)
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<String>()
        return comments.filter { comment in
            guard !seen.contains(comment.id), !comment.isDeleted else { return false }
            seen.insert(comment.id)
            return true
        }
    }

    private func adoptSignedInUser(uid: String, appleUserID: String?, displayName: String?) {
        guard currentUser.id != uid else { return }

        let now = Date()
        let name = nonEmpty(displayName) ?? currentUser.displayName
        let handle = ValidationUtil.isValidHandle(currentUser.handle) ? currentUser.handle : handleCandidate(from: name, fallback: uid)
        currentUser = AppUser(
            id: uid,
            displayName: name,
            handle: handle,
            bio: currentUser.bio,
            avatarUrl: currentUser.avatarUrl,
            appleUserId: appleUserID,
            humanLevel: currentUser.humanLevel,
            humanVerifiedPostRate: currentUser.humanVerifiedPostRate,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        users = mergeCurrentUser(into: users.filter { $0.id != initialCurrentUser.id })
    }

    private func adoptRemoteUser(_ remoteUser: AppUser, appleUserID: String?) {
        currentUser = remoteUser

        if let appleUserID, currentUser.appleUserId == nil {
            currentUser.appleUserId = appleUserID
        }

        users = mergeCurrentUser(into: users.filter { $0.id != initialCurrentUser.id })
    }

    private func mergeCurrentUser(into remoteUsers: [AppUser]) -> [AppUser] {
        var merged = remoteUsers.filter { !$0.isDeleted }
        if let index = merged.firstIndex(where: { $0.id == currentUser.id }) {
            merged[index] = currentUser
        } else {
            merged.insert(currentUser, at: 0)
        }
        return merged
    }

    private func handleCandidate(from displayName: String, fallback: String) -> String {
        let raw = displayName
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let fallbackSuffix = fallback
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        let safeFallback = fallbackSuffix.isEmpty ? "local" : String(fallbackSuffix)
        let candidate = raw.isEmpty ? "user_\(safeFallback)" : String(raw.prefix(20))
        return ValidationUtil.isValidHandle(candidate) ? candidate : "user_\(safeFallback)"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func runRemoteWrite(_ operation: @escaping () async throws -> Void) {
        guard isRemoteSyncEnabled else { return }

        Task {
            do {
                try await operation()
            } catch {
                await MainActor.run {
                    self.recordRemoteError(error)
                }
            }
        }
    }

    private func recordRemoteError(_ error: Error) {
        lastSyncErrorMessage = error.localizedDescription
    }
}

private extension Post {
    func replacingBody(_ body: String) -> Post {
        Post(
            id: id,
            userId: userId,
            body: body,
            humanScore: humanScore,
            humanBadge: humanBadge,
            inputDurationMs: inputDurationMs,
            characterCount: body.count,
            editCount: editCount,
            deleteCount: deleteCount,
            suspiciousBulkInputCount: suspiciousBulkInputCount,
            appCheckVerified: appCheckVerified,
            likeCount: likeCount,
            commentCount: commentCount,
            createdAt: createdAt,
            updatedAt: Date(),
            isDeleted: isDeleted
        )
    }

    func demoCopy(currentUserID: String, seedCurrentUserID: String) -> Post {
        Post(
            id: "demo-\(id)",
            userId: userId == seedCurrentUserID ? currentUserID : userId,
            body: body,
            humanScore: humanScore,
            humanBadge: humanBadge,
            inputDurationMs: inputDurationMs,
            characterCount: characterCount,
            editCount: editCount,
            deleteCount: deleteCount,
            suspiciousBulkInputCount: suspiciousBulkInputCount,
            appCheckVerified: appCheckVerified,
            likeCount: likeCount,
            commentCount: commentCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}

private extension Comment {
    func demoCopy(currentUserID: String, seedCurrentUserID: String) -> Comment {
        Comment(
            id: "demo-\(id)",
            postId: "demo-\(postId)",
            userId: userId == seedCurrentUserID ? currentUserID : userId,
            body: body,
            humanScore: humanScore,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted
        )
    }
}
