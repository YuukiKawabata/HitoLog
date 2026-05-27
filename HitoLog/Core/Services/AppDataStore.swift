import Combine
import Foundation

struct CommentPermissionState: Equatable {
    let canComment: Bool
    let message: String?
}

enum StarterPackCategory: String, CaseIterable, Identifiable {
    case writers
    case daily
    case creative
    case learning

    var id: String { rawValue }

    var title: String {
        switch self {
        case .writers:
            return "言葉を書く人"
        case .daily:
            return "日常ログ"
        case .creative:
            return "創作"
        case .learning:
            return "学び"
        }
    }

    var systemImage: String {
        switch self {
        case .writers:
            return "pencil.and.outline"
        case .daily:
            return "sun.max"
        case .creative:
            return "paintbrush"
        case .learning:
            return "book"
        }
    }

    var topic: String {
        switch self {
        case .writers:
            return "言葉"
        case .daily:
            return "日常ログ"
        case .creative:
            return "創作"
        case .learning:
            return "学び"
        }
    }
}

@MainActor
final class AppDataStore: ObservableObject {
    @Published private(set) var currentUser: AppUser
    @Published private(set) var users: [AppUser]
    @Published private(set) var posts: [Post]
    @Published private(set) var comments: [Comment]
    @Published private(set) var likedPostIDs: Set<String>
    @Published private(set) var bookmarkedPostIDs: Set<String>
    @Published private(set) var blockedUserIDs: Set<String>
    @Published private(set) var mutedUserIDs: Set<String>
    @Published private(set) var mutedWords: [MutedWord]
    @Published private(set) var topicRooms: [TopicRoom]
    @Published private(set) var followedTopicIDs: Set<String>
    @Published private(set) var followingUserIDs: Set<String>
    @Published private(set) var followerCountsByUserID: [String: Int]
    @Published private(set) var followingCountsByUserID: [String: Int]
    @Published private(set) var followersByUserID: [String: Set<String>]
    @Published private(set) var followingByUserID: [String: Set<String>]
    @Published private(set) var reportHistory: [ReportRecord]
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var adminReports: [ReportRecord] = []
    @Published private(set) var searchResults: [AppUser] = []
    @Published private(set) var topicSearchResults: [Post] = []
    @Published private(set) var topicRoomSearchResults: [TopicRoom] = []
    @Published private(set) var postSearchResults: [Post] = []
    @Published private(set) var hasMoreTimelinePosts = true
    @Published private(set) var isLoadingTimelinePage = false
    @Published private(set) var isRemoteSyncEnabled = false
    @Published private(set) var isDemoDataVisible = false
    @Published private(set) var lastSyncErrorMessage: String?

    private let remoteStore: FirebaseDataStore
    private let initialCurrentUser: AppUser
    private let initialUsers: [AppUser]
    private let initialPosts: [Post]
    private let initialComments: [Comment]
    private let initialLikedPostIDs: Set<String>
    private let initialBookmarkedPostIDs: Set<String>
    private let initialMutedWords: [MutedWord]
    private let initialTopicRooms: [TopicRoom]
    private let initialFollowedTopicIDs: Set<String>
    private let initialFollowingUserIDs: Set<String>
    private let initialFollowerCountsByUserID: [String: Int]
    private let initialFollowingCountsByUserID: [String: Int]
    private let initialFollowersByUserID: [String: Set<String>]
    private let initialFollowingByUserID: [String: Set<String>]
    private var remoteUserID: String?
    private var currentUserBeforeDemoData: AppUser?

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
            isVisiblePost(post)
            && post.userId != currentUser.id
            && !blockedUserIDs.contains(post.userId)
            && !mutedUserIDs.contains(post.userId)
            && !containsMutedWord(post)
            && (post.shareType == .original || sourcePost(for: post) != nil)
        }
        .sorted {
            $0.createdAt > $1.createdAt
        }
    }

    var followingTimelinePosts: [Post] {
        timelinePosts.filter { post in
            followingUserIDs.contains(post.userId)
        }
    }

    var recommendedTimelinePosts: [Post] {
        timelinePosts
            .filter { post in
                !followingUserIDs.contains(post.userId) || recommendationScore(for: post) >= 28
            }
            .sorted {
                recommendationScore(for: $0) > recommendationScore(for: $1)
            }
    }

    var followedTopicTimelinePosts: [Post] {
        guard !followedTopicIDs.isEmpty else { return [] }
        return timelinePosts.filter { post in
            !Set(post.topics).intersection(followedTopicIDs).isEmpty
        }
    }

    var discoverTopicRooms: [TopicRoom] {
        topicRooms
            .filter { $0.moderationStatus == .active }
            .sorted { first, second in
                if first.isOfficial != second.isOfficial {
                    return first.isOfficial
                }
                if isFollowingTopic(first.topic) != isFollowingTopic(second.topic) {
                    return isFollowingTopic(first.topic)
                }
                if first.postCount != second.postCount {
                    return first.postCount > second.postCount
                }
                return first.topic.localizedCaseInsensitiveCompare(second.topic) == .orderedAscending
            }
    }

    var timelineVerifiedPostRate: Double {
        guard !timelinePosts.isEmpty else { return 0 }
        let verifiedCount = timelinePosts.filter { $0.humanBadge == .verified }.count
        return Double(verifiedCount) / Double(timelinePosts.count)
    }

    var unreadNotificationCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    var followSuggestions: [AppUser] {
        starterPackCandidates()
            .sorted {
                let firstScore = userRecommendationScore($0)
                let secondScore = userRecommendationScore($1)
                if firstScore != secondScore {
                    return firstScore > secondScore
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
    }

    var bookmarkedPosts: [Post] {
        posts
            .filter {
                bookmarkedPostIDs.contains($0.id)
                && isVisiblePost($0)
                && !blockedUserIDs.contains($0.userId)
                && !mutedUserIDs.contains($0.userId)
                && !containsMutedWord($0)
                && ($0.shareType == .original || sourcePost(for: $0) != nil)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var repostedSourcePostIDs: Set<String> {
        Set(posts.compactMap { post in
            post.userId == currentUser.id && post.shareType == .repost && isVisiblePost(post)
                ? post.sourcePostID
                : nil
        })
    }

    var trendingTopics: [TopicTrend] {
        var counts: [String: Int] = [:]
        for post in timelinePosts + posts.filter({ $0.userId == currentUser.id && isVisiblePost($0) && !containsMutedWord($0) }) {
            for topic in post.topics {
                counts[topic, default: 0] += 1
            }
        }

        return counts
            .map { TopicTrend(topic: $0.key, postCount: $0.value) }
            .sorted {
                if $0.postCount != $1.postCount {
                    return $0.postCount > $1.postCount
                }
                return $0.topic < $1.topic
            }
            .prefix(12)
            .map { $0 }
    }

    init(remoteStore: FirebaseDataStore = FirebaseDataStore()) {
        let seed = MockDataStore()
        self.remoteStore = remoteStore
        self.initialCurrentUser = seed.currentUser
        self.initialUsers = seed.users
        self.initialPosts = seed.posts
        self.initialComments = seed.comments
        self.initialLikedPostIDs = seed.likedPostIDs
        self.initialBookmarkedPostIDs = seed.likedPostIDs
        self.initialMutedWords = []
        self.initialTopicRooms = Self.topicRooms(from: seed.posts)
        self.initialFollowedTopicIDs = Set(StarterPackCategory.allCases.prefix(2).map(\.topic))
        self.initialFollowingUserIDs = seed.followingUserIDs
        self.initialFollowerCountsByUserID = seed.followerCountsByUserID
        self.initialFollowingCountsByUserID = seed.followingCountsByUserID
        self.initialFollowersByUserID = seed.followersByUserID
        self.initialFollowingByUserID = seed.followingByUserID
        self.currentUser = seed.currentUser
        self.users = seed.users
        self.posts = seed.posts
        self.comments = seed.comments
        self.likedPostIDs = seed.likedPostIDs
        self.bookmarkedPostIDs = seed.likedPostIDs
        self.blockedUserIDs = seed.blockedUserIDs
        self.mutedUserIDs = seed.mutedUserIDs
        self.mutedWords = []
        self.topicRooms = initialTopicRooms
        self.followedTopicIDs = initialFollowedTopicIDs
        self.followingUserIDs = seed.followingUserIDs
        self.followerCountsByUserID = seed.followerCountsByUserID
        self.followingCountsByUserID = seed.followingCountsByUserID
        self.followersByUserID = seed.followersByUserID
        self.followingByUserID = seed.followingByUserID
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
        posts.first {
            $0.id == id
            && isVisiblePost($0)
            && !blockedUserIDs.contains($0.userId)
            && !mutedUserIDs.contains($0.userId)
            && !containsMutedWord($0)
        }
    }

    func sourcePost(for post: Post) -> Post? {
        guard let sourcePostID = post.sourcePostID else { return nil }
        return posts.first {
            $0.id == sourcePostID
            && isVisiblePost($0)
            && !blockedUserIDs.contains($0.userId)
            && !mutedUserIDs.contains($0.userId)
            && !containsMutedWord($0)
        }
    }

    func shareTargetPost(for post: Post) -> Post {
        guard let sourcePost = sourcePost(for: post) else { return post }
        return sourcePost
    }

    func isReposted(_ postID: String) -> Bool {
        repostedSourcePostIDs.contains(postID)
    }

    func commentPermissionStatus(for post: Post) -> CommentPermissionState {
        guard canCurrentUserCreateContent else {
            return CommentPermissionState(canComment: false, message: "このアカウントは現在コメントできません。")
        }

        switch post.commentPermission {
        case .everyone:
            return CommentPermissionState(canComment: true, message: nil)
        case .following:
            if post.userId == currentUser.id || followingByUserID[post.userId, default: []].contains(currentUser.id) {
                return CommentPermissionState(canComment: true, message: nil)
            }
            return CommentPermissionState(canComment: false, message: "この投稿は、投稿者がフォローしているユーザーだけコメントできます。")
        case .closed:
            return CommentPermissionState(canComment: false, message: "この投稿へのコメントは閉じられています。")
        }
    }

    func commentPermissionStatus(for postID: String) -> CommentPermissionState {
        guard let post = post(for: postID) else {
            return CommentPermissionState(canComment: false, message: "投稿が見つかりません。")
        }
        return commentPermissionStatus(for: post)
    }

    func insert(_ post: Post) {
        guard canCurrentUserCreateContent else { return }
        posts.insert(post, at: 0)
        refreshLocalTopicRoomsFromPosts()
        runRemoteWrite {
            try await self.remoteStore.savePost(post)
        }
    }

    func updatePost(postID: String, body: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              canCurrentUserCreateContent,
              let index = posts.firstIndex(where: { $0.id == postID && $0.userId == currentUser.id && isVisiblePost($0) }) else {
            return
        }

        posts[index] = posts[index].replacingBody(trimmedBody)
        refreshLocalTopicRoomsFromPosts()

        guard !postID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.updatePostBody(postID: postID, body: trimmedBody)
        }
    }

    func deletePost(postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID && $0.userId == currentUser.id && isVisiblePost($0) }) else {
            return
        }

        let deletedPost = posts[index]
        posts[index].isDeleted = true
        posts[index].updatedAt = Date()
        refreshLocalTopicRoomsFromPosts()
        likedPostIDs.remove(postID)
        if let sourcePostID = deletedPost.sourcePostID {
            adjustShareCount(sourcePostID: sourcePostID, shareType: deletedPost.shareType, amount: -1)
        }

        guard !postID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.deletePost(postID: postID)
        }
    }

    func toggleRepost(for postID: String) {
        guard canCurrentUserCreateContent,
              let requestedPost = post(for: postID) else {
            return
        }

        let sourcePost = shareTargetPost(for: requestedPost)
        if let existingRepost = posts.first(where: {
            $0.userId == currentUser.id
                && $0.shareType == .repost
                && $0.sourcePostID == sourcePost.id
                && isVisiblePost($0)
        }) {
            deletePost(postID: existingRepost.id)
            return
        }

        let now = Date()
        let repost = Post(
            id: "repost_\(currentUser.id)_\(sourcePost.id)",
            userId: currentUser.id,
            body: "",
            topics: sourcePost.topics,
            searchTokens: sourcePost.searchTokens,
            shareType: .repost,
            sourcePostID: sourcePost.id,
            sourceUserID: sourcePost.userId,
            commentPermission: .closed,
            humanScore: 100,
            humanBadge: .verified,
            inputDurationMs: 0,
            characterCount: 0,
            editCount: 0,
            deleteCount: 0,
            suspiciousBulkInputCount: 0,
            appCheckVerified: true,
            likeCount: 0,
            commentCount: 0,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )

        posts.insert(repost, at: 0)
        adjustShareCount(sourcePostID: sourcePost.id, shareType: .repost, amount: 1)
        refreshLocalTopicRoomsFromPosts()

        guard !sourcePost.id.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.savePost(repost)
        }
    }

    func quotePost(sourcePostID: String, body: String, metrics: TypingMetrics) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              trimmedBody.count <= AppConstants.maxPostLength,
              canCurrentUserCreateContent,
              let requestedPost = post(for: sourcePostID) else {
            return
        }

        let sourcePost = shareTargetPost(for: requestedPost)
        let input = HumanScoreInput(
            inputDurationMs: metrics.inputDurationMs,
            characterCount: trimmedBody.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appAttestVerified: true,
            accountAgeDays: currentUser.accountAgeDays,
            recentPostCount: recentPostCount
        )
        let humanScoreService = HumanScoreService()
        let score = humanScoreService.calculate(input: input)
        let now = Date()
        let quote = Post(
            id: UUID().uuidString,
            userId: currentUser.id,
            body: trimmedBody,
            shareType: .quote,
            sourcePostID: sourcePost.id,
            sourceUserID: sourcePost.userId,
            commentPermission: .everyone,
            humanScore: score,
            humanBadge: humanScoreService.badge(for: score),
            inputDurationMs: metrics.inputDurationMs,
            characterCount: trimmedBody.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appCheckVerified: true,
            likeCount: 0,
            commentCount: 0,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )

        posts.insert(quote, at: 0)
        adjustShareCount(sourcePostID: sourcePost.id, shareType: .quote, amount: 1)
        refreshLocalTopicRoomsFromPosts()

        guard !sourcePost.id.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.savePost(quote)
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
        guard canCurrentUserCreateContent,
              let index = posts.firstIndex(where: { $0.id == postID && isVisiblePost($0) }) else { return }

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

    func isBookmarked(_ postID: String) -> Bool {
        bookmarkedPostIDs.contains(postID)
    }

    func toggleBookmark(for postID: String) {
        guard canCurrentUserCreateContent,
              posts.contains(where: { $0.id == postID && isVisiblePost($0) }) else {
            return
        }

        let isBookmarked: Bool
        if bookmarkedPostIDs.contains(postID) {
            bookmarkedPostIDs.remove(postID)
            isBookmarked = false
        } else {
            bookmarkedPostIDs.insert(postID)
            isBookmarked = true
        }

        guard !postID.hasPrefix("demo-") else { return }
        let userID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setBookmark(postID: postID, userID: userID, isBookmarked: isBookmarked)
        }
    }

    func comments(for postID: String) -> [Comment] {
        comments
            .filter {
                $0.postId == postID
                && isVisibleComment($0)
                && !containsMutedWord($0)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(body: String, to postID: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty,
              canCurrentUserCreateContent,
              commentPermissionStatus(for: postID).canComment else {
            return
        }

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

    func deleteComment(commentID: String) {
        guard let index = comments.firstIndex(where: { $0.id == commentID && $0.userId == currentUser.id && isVisibleComment($0) }) else {
            return
        }

        let postID = comments[index].postId
        comments[index].isDeleted = true
        comments[index].updatedAt = Date()
        adjustCommentCount(postID: postID, amount: -1)

        guard !commentID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.deleteComment(commentID: commentID)
        }
    }

    func hideComment(commentID: String) {
        guard let index = comments.firstIndex(where: { $0.id == commentID && isVisibleComment($0) }),
              let post = posts.first(where: { $0.id == comments[index].postId }),
              post.userId == currentUser.id else {
            return
        }

        let postID = comments[index].postId
        comments[index].moderationStatus = .hidden
        comments[index].hiddenReason = "post_owner_hidden"
        comments[index].hiddenAt = Date()
        comments[index].updatedAt = Date()
        adjustCommentCount(postID: postID, amount: -1)

        guard !commentID.hasPrefix("demo-") else { return }
        runRemoteWrite {
            try await self.remoteStore.hideComment(commentID: commentID, reason: "post_owner_hidden")
        }
    }

    func postCount(for userID: String) -> Int {
        posts.filter { $0.userId == userID && isVisiblePost($0) && !containsMutedWord($0) }.count
    }

    func isFollowing(_ userID: String) -> Bool {
        followingUserIDs.contains(userID)
    }

    func followerCount(for userID: String) -> Int {
        followerCountsByUserID[userID] ?? user(for: userID)?.followerCount ?? 0
    }

    func followingCount(for userID: String) -> Int {
        followingCountsByUserID[userID] ?? user(for: userID)?.followingCount ?? 0
    }

    func followers(for userID: String) -> [AppUser] {
        sortedUsers(for: followersByUserID[userID, default: []])
    }

    func following(for userID: String) -> [AppUser] {
        sortedUsers(for: followingByUserID[userID, default: []])
    }

    func toggleFollow(userID: String) {
        guard userID != currentUser.id,
              let targetUser = user(for: userID),
              canCurrentUserCreateContent,
              !targetUser.isSuspended,
              !blockedUserIDs.contains(userID) else {
            return
        }

        let isFollowing = followingUserIDs.contains(userID)
        if isFollowing {
            removeFollowLocally(followerID: currentUser.id, followeeID: userID)
        } else {
            addFollowLocally(followerID: currentUser.id, followeeID: userID)
        }

        guard !shouldSkipRemoteFollowWrite(for: userID) else { return }
        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setFollow(
                followerID: currentUserID,
                followeeID: userID,
                isFollowing: !isFollowing
            )
        }
    }

    func blockedUsers() -> [AppUser] {
        users.filter { blockedUserIDs.contains($0.id) }
    }

    func mutedUsers() -> [AppUser] {
        users.filter { mutedUserIDs.contains($0.id) }
    }

    func addMutedWord(_ rawWord: String) {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWord = MutedWordNormalizer.normalize(word)
        guard !word.isEmpty,
              !normalizedWord.isEmpty,
              word.count <= AppConstants.maxMutedWordLength,
              !mutedWords.contains(where: { $0.normalizedWord == normalizedWord }) else {
            return
        }

        let mutedWord = MutedWord(
            id: MutedWord.makeID(userID: currentUser.id, normalizedWord: normalizedWord),
            userID: currentUser.id,
            word: word,
            normalizedWord: normalizedWord,
            createdAt: Date()
        )
        mutedWords.insert(mutedWord, at: 0)
        refilterSearchResults()

        runRemoteWrite {
            try await self.remoteStore.setMutedWord(mutedWord, isMuted: true)
        }
    }

    func removeMutedWord(_ mutedWord: MutedWord) {
        mutedWords.removeAll { $0.id == mutedWord.id }
        refilterSearchResults()

        runRemoteWrite {
            try await self.remoteStore.setMutedWord(mutedWord, isMuted: false)
        }
    }

    func isFollowingTopic(_ topic: String) -> Bool {
        guard let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) else { return false }
        return followedTopicIDs.contains(normalizedTopic)
    }

    func toggleTopicFollow(topic: String) {
        guard canCurrentUserCreateContent,
              let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) else {
            return
        }

        let isFollowing = followedTopicIDs.contains(normalizedTopic)
        if isFollowing {
            followedTopicIDs.remove(normalizedTopic)
            adjustTopicFollowerCount(topic: normalizedTopic, amount: -1)
        } else {
            followedTopicIDs.insert(normalizedTopic)
            ensureTopicRoomExists(topic: normalizedTopic)
            adjustTopicFollowerCount(topic: normalizedTopic, amount: 1)
        }

        let userID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setTopicFollow(
                userID: userID,
                topic: normalizedTopic,
                isFollowing: !isFollowing
            )
        }
    }

    func topicRoom(for topic: String) -> TopicRoom {
        let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) ?? topic
        return topicRooms.first { $0.topic == normalizedTopic } ?? Self.defaultTopicRoom(topic: normalizedTopic)
    }

    func topicRoomPosts(for topic: String, sort: TopicRoomPostSort) -> [Post] {
        guard let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) else { return [] }
        let visiblePosts = posts.filter {
            isVisiblePost($0)
            && $0.topics.contains(normalizedTopic)
            && !blockedUserIDs.contains($0.userId)
            && !mutedUserIDs.contains($0.userId)
            && !containsMutedWord($0)
            && ($0.shareType == .original || sourcePost(for: $0) != nil)
        }

        switch sort {
        case .latest:
            return visiblePosts.sorted { $0.createdAt > $1.createdAt }
        case .popular:
            return visiblePosts.sorted {
                let firstScore = recommendationScore(for: $0)
                let secondScore = recommendationScore(for: $1)
                if firstScore != secondScore {
                    return firstScore > secondScore
                }
                return $0.createdAt > $1.createdAt
            }
        }
    }

    func searchTopicRooms(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            topicRoomSearchResults = []
            return
        }

        let normalized = MutedWordNormalizer.normalize(trimmed.replacingOccurrences(of: "#", with: ""))
        topicRoomSearchResults = discoverTopicRooms.filter { room in
            MutedWordNormalizer.normalize([room.topic, room.title, room.description].joined(separator: " "))
                .contains(normalized)
        }
    }

    func loadTopicRoomPosts(topic: String) async {
        guard isRemoteSyncEnabled,
              let normalizedTopic = TopicExtractor.normalizedTopicQuery(from: topic) else {
            return
        }

        do {
            let page = try await remoteStore.loadTopicPosts(topic: normalizedTopic)
            posts = uniquePosts(posts + page.posts)
            users = mergeCurrentUser(into: uniqueUsers(users + page.users))
            refreshLocalTopicRoomsFromPosts()
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func starterPackUsers(for category: StarterPackCategory) -> [AppUser] {
        starterPackCandidates()
            .sorted {
                let firstScore = starterPackScore(for: $0, category: category)
                let secondScore = starterPackScore(for: $1, category: category)
                if firstScore != secondScore {
                    return firstScore > secondScore
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            .prefix(8)
            .map { $0 }
    }

    func visibleProfilePosts(for userID: String) -> [Post] {
        posts
            .filter {
                $0.userId == userID
                && isVisiblePost($0)
                && !blockedUserIDs.contains($0.userId)
                && !mutedUserIDs.contains($0.userId)
                && !containsMutedWord($0)
                && ($0.shareType == .original || sourcePost(for: $0) != nil)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func block(_ userID: String) {
        guard userID != currentUser.id else { return }
        blockedUserIDs.insert(userID)
        mutedUserIDs.remove(userID)
        let wasFollowing = followingUserIDs.contains(userID)
        if wasFollowing {
            removeFollowLocally(followerID: currentUser.id, followeeID: userID)
        }

        let currentUserID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.setBlock(blockerID: currentUserID, blockedUserID: userID, isBlocked: true)
            try await self.remoteStore.setMute(muterID: currentUserID, mutedUserID: userID, isMuted: false)
            if wasFollowing {
                try await self.remoteStore.setFollow(followerID: currentUserID, followeeID: userID, isFollowing: false)
            }
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
        addReport(targetType: .other, targetID: nil, targetOwnerID: nil, targetDescription: targetDescription, reason: reason)
    }

    func addReport(
        targetType: ReportTargetType,
        targetID: String?,
        targetOwnerID: String?,
        targetDescription: String,
        reason: String
    ) {
        let report = ReportRecord(
            id: UUID().uuidString,
            targetDescription: targetDescription,
            reason: reason,
            createdAt: Date(),
            status: "確認待ち",
            reporterID: currentUser.id,
            targetType: targetType,
            targetID: targetID,
            targetOwnerID: targetOwnerID
        )
        reportHistory.insert(report, at: 0)

        let reporterID = currentUser.id
        runRemoteWrite {
            try await self.remoteStore.addReport(report, reporterID: reporterID)
        }
    }

    func loadComments(for postID: String) async {
        guard isRemoteSyncEnabled, !postID.hasPrefix("demo-") else { return }

        do {
            let remoteComments = try await remoteStore.loadComments(postID: postID)
            comments = uniqueComments(comments.filter { $0.postId != postID } + remoteComments)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func loadMoreTimelinePosts() async {
        guard isRemoteSyncEnabled, hasMoreTimelinePosts, !isLoadingTimelinePage else { return }
        guard let remoteUserID else { return }

        isLoadingTimelinePage = true
        defer { isLoadingTimelinePage = false }

        do {
            let page = try await remoteStore.loadTimelinePosts(
                currentUserID: remoteUserID,
                before: timelinePaginationCursorDate()
            )
            posts = uniquePosts(posts + page.posts)
            users = mergeCurrentUser(into: uniqueUsers(users + page.users))
            hasMoreTimelinePosts = page.hasMore
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func loadFollowLists(for userID: String) async {
        guard isRemoteSyncEnabled else { return }

        do {
            let state = try await remoteStore.loadFollowState(userID: userID)
            users = mergeCurrentUser(into: uniqueUsers(users + state.users))
            followersByUserID[userID] = state.followerIDs
            followingByUserID[userID] = state.followingIDs
            if userID == currentUser.id {
                followingUserIDs = state.followingIDs
            }
            rebuildFollowCounts()
            applyUserCountsFromFollowState(userID: userID)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func loadNotifications() async {
        guard isRemoteSyncEnabled, let remoteUserID else { return }

        do {
            notifications = try await remoteStore.loadNotifications(recipientID: remoteUserID)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func loadBookmarkedPosts() async {
        guard isRemoteSyncEnabled, let remoteUserID else { return }

        do {
            let state = try await remoteStore.loadBookmarkedPosts(userID: remoteUserID)
            bookmarkedPostIDs = state.postIDs
            posts = uniquePosts(posts + state.posts)
            users = mergeCurrentUser(into: uniqueUsers(users + state.users))
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func markNotificationsRead() async {
        let unreadIDs = notifications.filter { !$0.isRead }.map(\.id)
        guard !unreadIDs.isEmpty else { return }

        let now = Date()
        for index in notifications.indices where unreadIDs.contains(notifications[index].id) {
            notifications[index].isRead = true
            notifications[index].readAt = now
        }

        guard isRemoteSyncEnabled else { return }
        do {
            try await remoteStore.markNotificationsRead(notificationIDs: unreadIDs)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func searchUsers(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }

        if isRemoteSyncEnabled {
            do {
                searchResults = try await remoteStore.searchUsers(query: trimmed)
                    .filter {
                        $0.id != currentUser.id
                        && !$0.isSuspended
                        && !$0.isDeleted
                        && !blockedUserIDs.contains($0.id)
                        && !mutedUserIDs.contains($0.id)
                    }
                users = mergeCurrentUser(into: uniqueUsers(users + searchResults))
                lastSyncErrorMessage = nil
                return
            } catch {
                recordRemoteError(error)
            }
        }

        let needle = trimmed.lowercased()
        searchResults = users.filter { user in
            user.id != currentUser.id
            && !user.isDeleted
            && !user.isSuspended
            && !blockedUserIDs.contains(user.id)
            && !mutedUserIDs.contains(user.id)
            && (user.displayNameLowercase.contains(needle) || user.handleLowercase.contains(needle))
        }
    }

    func searchTopicPosts(query: String) async {
        guard let topic = TopicExtractor.normalizedTopicQuery(from: query) else {
            topicSearchResults = []
            return
        }

        if isRemoteSyncEnabled {
            do {
                let page = try await remoteStore.loadTopicPosts(topic: topic)
                topicSearchResults = page.posts.filter { post in
                    post.userId != currentUser.id
                    && post.topics.contains(topic)
                    && !blockedUserIDs.contains(post.userId)
                    && !mutedUserIDs.contains(post.userId)
                    && !containsMutedWord(post)
                }
                posts = uniquePosts(posts + page.posts)
                users = mergeCurrentUser(into: uniqueUsers(users + page.users))
                lastSyncErrorMessage = nil
                return
            } catch {
                recordRemoteError(error)
            }
        }

        topicSearchResults = posts
            .filter {
                isVisiblePost($0)
                && $0.topics.contains(topic)
                && $0.userId != currentUser.id
                && !blockedUserIDs.contains($0.userId)
                && !mutedUserIDs.contains($0.userId)
                && !containsMutedWord($0)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func searchPosts(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            postSearchResults = []
            return
        }

        if isRemoteSyncEnabled {
            do {
                let page = try await remoteStore.searchPosts(query: trimmed)
                postSearchResults = page.posts.filter { post in
                    post.userId != currentUser.id
                    && !blockedUserIDs.contains(post.userId)
                    && !mutedUserIDs.contains(post.userId)
                    && !containsMutedWord(post)
                    && PostSearchTokenizer.matches(post, query: trimmed)
                }
                posts = uniquePosts(posts + page.posts)
                users = mergeCurrentUser(into: uniqueUsers(users + page.users))
                lastSyncErrorMessage = nil
                return
            } catch {
                recordRemoteError(error)
            }
        }

        postSearchResults = posts
            .filter {
                isVisiblePost($0)
                && $0.userId != currentUser.id
                && !blockedUserIDs.contains($0.userId)
                && !mutedUserIDs.contains($0.userId)
                && !containsMutedWord($0)
                && PostSearchTokenizer.matches($0, query: trimmed)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func loadAdminReports() async {
        guard currentUser.isAdmin, isRemoteSyncEnabled else { return }

        do {
            adminReports = try await remoteStore.loadAdminReports()
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func resolveReport(_ report: ReportRecord, status: String, adminNote: String = "") async {
        guard currentUser.isAdmin else { return }

        updateAdminReportLocally(report.id, status: status, adminNote: adminNote)
        guard isRemoteSyncEnabled else { return }

        do {
            try await remoteStore.resolveReport(
                reportID: report.id,
                status: status,
                adminNote: adminNote,
                adminID: currentUser.id
            )
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func hideReportedContent(_ report: ReportRecord, reason: String = "通報対応") async {
        guard currentUser.isAdmin, let targetID = report.targetID else { return }

        switch report.targetType {
        case .post:
            if let index = posts.firstIndex(where: { $0.id == targetID }) {
                posts[index].moderationStatus = .hidden
                posts[index].hiddenReason = reason
                posts[index].hiddenAt = Date()
            }
        case .comment:
            if let index = comments.firstIndex(where: { $0.id == targetID }) {
                let postID = comments[index].postId
                comments[index].moderationStatus = .hidden
                comments[index].hiddenReason = reason
                comments[index].hiddenAt = Date()
                adjustCommentCount(postID: postID, amount: -1)
            }
        case .user, .other:
            return
        }

        await resolveReport(report, status: "対応済み", adminNote: reason)
        guard isRemoteSyncEnabled else { return }

        do {
            try await remoteStore.hideContent(
                targetType: report.targetType,
                targetID: targetID,
                reason: reason,
                adminID: currentUser.id
            )
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func suspendReportedUser(_ report: ReportRecord, reason: String = "通報対応") async {
        guard currentUser.isAdmin else { return }
        let userID = report.targetType == .user ? report.targetID : report.targetOwnerID
        guard let userID, userID != currentUser.id else { return }

        if let index = users.firstIndex(where: { $0.id == userID }) {
            users[index].isSuspended = true
        }

        await resolveReport(report, status: "対応済み", adminNote: reason)
        guard isRemoteSyncEnabled else { return }

        do {
            try await remoteStore.setUserSuspended(userID: userID, isSuspended: true, reason: reason, adminID: currentUser.id)
            lastSyncErrorMessage = nil
        } catch {
            recordRemoteError(error)
        }
    }

    func resetLocalAccount() {
        currentUser = initialCurrentUser
        users = initialUsers
        posts = initialPosts
        comments = initialComments
        likedPostIDs = initialLikedPostIDs
        bookmarkedPostIDs = initialBookmarkedPostIDs
        blockedUserIDs = []
        mutedUserIDs = []
        mutedWords = initialMutedWords
        topicRooms = initialTopicRooms
        followedTopicIDs = initialFollowedTopicIDs
        followingUserIDs = initialFollowingUserIDs
        followerCountsByUserID = initialFollowerCountsByUserID
        followingCountsByUserID = initialFollowingCountsByUserID
        followersByUserID = initialFollowersByUserID
        followingByUserID = initialFollowingByUserID
        reportHistory = []
        notifications = []
        adminReports = []
        searchResults = []
        topicSearchResults = []
        topicRoomSearchResults = []
        postSearchResults = []
        hasMoreTimelinePosts = true
        isLoadingTimelinePage = false
        isDemoDataVisible = false
        currentUserBeforeDemoData = nil
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
        bookmarkedPostIDs.removeAll()
        blockedUserIDs.removeAll()
        mutedUserIDs.removeAll()
        mutedWords.removeAll()
        topicRooms = initialTopicRooms
        followedTopicIDs.removeAll()
        followingUserIDs.removeAll()
        followerCountsByUserID.removeAll()
        followingCountsByUserID.removeAll()
        followersByUserID.removeAll()
        followingByUserID.removeAll()
        notifications.removeAll()
        adminReports.removeAll()
        searchResults.removeAll()
        topicSearchResults.removeAll()
        topicRoomSearchResults.removeAll()
        postSearchResults.removeAll()
        hasMoreTimelinePosts = false
        isLoadingTimelinePage = false
    }

    func showScreenshotDemoData() {
        if !isDemoDataVisible {
            currentUserBeforeDemoData = currentUser
        }
        isDemoDataVisible = true
        applyScreenshotDemoData()
    }

    func hideScreenshotDemoData() async {
        isDemoDataVisible = false
        restoreCurrentUserAfterDemoData()

        if isRemoteSyncEnabled {
            do {
                try await reloadRemoteSnapshot()
            } catch {
                removeLocalDemoData()
                recordRemoteError(error)
            }
        } else {
            currentUser = initialCurrentUser
            users = initialUsers
            posts = initialPosts
            comments = initialComments
            likedPostIDs = initialLikedPostIDs
            bookmarkedPostIDs = initialBookmarkedPostIDs
            blockedUserIDs = []
            mutedUserIDs = []
            mutedWords = initialMutedWords
            topicRooms = initialTopicRooms
            followedTopicIDs = initialFollowedTopicIDs
            followingUserIDs = initialFollowingUserIDs
            followerCountsByUserID = initialFollowerCountsByUserID
            followingCountsByUserID = initialFollowingCountsByUserID
            followersByUserID = initialFollowersByUserID
            followingByUserID = initialFollowingByUserID
            reportHistory = []
            notifications = []
            adminReports = []
            searchResults = []
            topicSearchResults = []
            topicRoomSearchResults = []
            postSearchResults = []
            hasMoreTimelinePosts = true
            isLoadingTimelinePage = false
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
        bookmarkedPostIDs = snapshot.bookmarkedPostIDs
        blockedUserIDs = snapshot.blockedUserIDs
        mutedUserIDs = snapshot.mutedUserIDs
        mutedWords = snapshot.mutedWords
        topicRooms = Self.mergedTopicRooms(remoteRooms: snapshot.topicRooms, posts: snapshot.posts, followedTopicIDs: snapshot.followedTopicIDs)
        followedTopicIDs = snapshot.followedTopicIDs
        followingUserIDs = snapshot.followingUserIDs
        followerCountsByUserID = snapshot.followerCountsByUserID
        followingCountsByUserID = snapshot.followingCountsByUserID
        followersByUserID = snapshot.followersByUserID
        followingByUserID = snapshot.followingByUserID
        reportHistory = snapshot.reports
        notifications = snapshot.notifications
        hasMoreTimelinePosts = snapshot.hasMorePosts
        if currentUser.isAdmin {
            adminReports = snapshot.adminReports
        } else {
            adminReports = []
        }
        if isDemoDataVisible {
            applyScreenshotDemoData()
        }
        lastSyncErrorMessage = nil
    }

    private func applyScreenshotDemoData() {
        let seed = MockDataStore()
        let seedCurrentUserID = seed.currentUser.id
        let activeCurrentUserID = currentUser.id
        let demoUsers = seed.users
            .filter { $0.id != seedCurrentUserID && $0.id != currentUser.id }

        currentUser = seed.currentUser.demoProfileCopy(
            currentUserID: activeCurrentUserID,
            appleUserID: currentUser.appleUserId
        )
        users = mergeCurrentUser(into: uniqueUsers(users + demoUsers))
        posts = uniquePosts(posts.filter { !$0.id.hasPrefix("demo-") } + seed.posts.map { post in
            post.demoCopy(currentUserID: activeCurrentUserID, seedCurrentUserID: seedCurrentUserID)
        })
        comments = uniqueComments(comments.filter { !$0.id.hasPrefix("demo-") } + seed.comments.map { comment in
            comment.demoCopy(currentUserID: activeCurrentUserID, seedCurrentUserID: seedCurrentUserID)
        })
        likedPostIDs = Set(likedPostIDs.filter { !$0.hasPrefix("demo-") })
        likedPostIDs.formUnion(seed.likedPostIDs.map { "demo-\($0)" })
        bookmarkedPostIDs = Set(bookmarkedPostIDs.filter { !$0.hasPrefix("demo-") })
        bookmarkedPostIDs.formUnion(seed.likedPostIDs.map { "demo-\($0)" })
        blockedUserIDs.subtract(demoUsers.map(\.id))
        mutedUserIDs.subtract(demoUsers.map(\.id))
        mergeDemoFollows(from: seed, activeCurrentUserID: activeCurrentUserID, seedCurrentUserID: seedCurrentUserID)
        refreshLocalTopicRoomsFromPosts()
    }

    private func restoreCurrentUserAfterDemoData() {
        if let currentUserBeforeDemoData {
            currentUser = currentUserBeforeDemoData
            self.currentUserBeforeDemoData = nil
        }
    }

    private func removeLocalDemoData() {
        let demoUserIDs = Set(MockDataStore().users.map(\.id))
        users = mergeCurrentUser(into: users.filter { !demoUserIDs.contains($0.id) })
        posts = posts.filter { !$0.id.hasPrefix("demo-") }
        comments = comments.filter { !$0.id.hasPrefix("demo-") }
        likedPostIDs = Set(likedPostIDs.filter { !$0.hasPrefix("demo-") })
        bookmarkedPostIDs = Set(bookmarkedPostIDs.filter { !$0.hasPrefix("demo-") })
        blockedUserIDs.subtract(demoUserIDs)
        mutedUserIDs.subtract(demoUserIDs)
        removeFollows(involving: demoUserIDs)
        refreshLocalTopicRoomsFromPosts()
    }

    private func ensureTopicRoomExists(topic: String) {
        guard !topicRooms.contains(where: { $0.topic == topic }) else { return }
        topicRooms.append(Self.defaultTopicRoom(topic: topic, postCount: 0, followerCount: followedTopicIDs.contains(topic) ? 1 : 0))
        topicRooms = Self.mergedTopicRooms(remoteRooms: topicRooms, posts: posts, followedTopicIDs: followedTopicIDs)
    }

    private func refreshLocalTopicRoomsFromPosts() {
        topicRooms = Self.mergedTopicRooms(remoteRooms: topicRooms, posts: posts, followedTopicIDs: followedTopicIDs)
        refilterSearchResults()
    }

    private func adjustTopicFollowerCount(topic: String, amount: Int) {
        ensureTopicRoomExists(topic: topic)
        guard let index = topicRooms.firstIndex(where: { $0.topic == topic }) else { return }
        topicRooms[index].followerCount = max(topicRooms[index].followerCount + amount, 0)
        topicRooms[index].updatedAt = Date()
    }

    private static func mergedTopicRooms(
        remoteRooms: [TopicRoom],
        posts: [Post],
        followedTopicIDs: Set<String>
    ) -> [TopicRoom] {
        let localRooms = topicRooms(from: posts, followedTopicIDs: followedTopicIDs)
        var roomsByTopic = Dictionary(uniqueKeysWithValues: localRooms.map { ($0.topic, $0) })

        for room in remoteRooms where room.moderationStatus == .active {
            if var existing = roomsByTopic[room.topic] {
                existing.title = room.title.isEmpty ? existing.title : room.title
                existing.description = room.description.isEmpty ? existing.description : room.description
                existing.postCount = max(existing.postCount, room.postCount)
                existing.followerCount = max(existing.followerCount, room.followerCount)
                existing.lastPostAt = [existing.lastPostAt, room.lastPostAt].compactMap { $0 }.max()
                existing.isOfficial = existing.isOfficial || room.isOfficial
                existing.updatedAt = max(existing.updatedAt, room.updatedAt)
                roomsByTopic[room.topic] = existing
            } else {
                roomsByTopic[room.topic] = room
            }
        }

        return roomsByTopic.values.sorted { first, second in
            if first.isOfficial != second.isOfficial {
                return first.isOfficial
            }
            if first.postCount != second.postCount {
                return first.postCount > second.postCount
            }
            return first.topic.localizedCaseInsensitiveCompare(second.topic) == .orderedAscending
        }
    }

    private static func topicRooms(from posts: [Post], followedTopicIDs: Set<String> = []) -> [TopicRoom] {
        var counts: [String: Int] = [:]
        var lastPostDates: [String: Date] = [:]

        for post in posts where !post.isDeleted && post.moderationStatus == .active {
            for topic in post.topics {
                counts[topic, default: 0] += 1
                lastPostDates[topic] = max(lastPostDates[topic] ?? Date.distantPast, post.createdAt)
            }
        }

        var roomsByTopic = Dictionary(uniqueKeysWithValues: TopicRoom.officialRooms().map { ($0.topic, $0) })
        for (topic, count) in counts {
            var room = roomsByTopic[topic] ?? defaultTopicRoom(topic: topic)
            room.postCount = count
            room.lastPostAt = lastPostDates[topic]
            room.updatedAt = lastPostDates[topic] ?? room.updatedAt
            roomsByTopic[topic] = room
        }

        for topic in followedTopicIDs where roomsByTopic[topic] == nil {
            roomsByTopic[topic] = defaultTopicRoom(topic: topic, followerCount: 1)
        }

        return Array(roomsByTopic.values)
    }

    private static func defaultTopicRoom(
        topic: String,
        postCount: Int = 0,
        followerCount: Int = 0
    ) -> TopicRoom {
        let now = Date()
        return TopicRoom(
            topic: topic,
            title: "#\(topic)",
            description: "",
            postCount: postCount,
            followerCount: followerCount,
            lastPostAt: nil,
            createdAt: now,
            updatedAt: now,
            isOfficial: false,
            moderationStatus: .active
        )
    }

    private func sortedUsers(for userIDs: Set<String>) -> [AppUser] {
        users
            .filter { userIDs.contains($0.id) && !$0.isDeleted }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private func addFollowLocally(followerID: String, followeeID: String) {
        guard followerID != followeeID else { return }
        followingByUserID[followerID, default: []].insert(followeeID)
        followersByUserID[followeeID, default: []].insert(followerID)
        if followerID == currentUser.id {
            followingUserIDs.insert(followeeID)
        }
        rebuildFollowCounts()
        applyUserCountsFromFollowState(userID: followerID)
        applyUserCountsFromFollowState(userID: followeeID)
    }

    private func removeFollowLocally(followerID: String, followeeID: String) {
        followingByUserID[followerID]?.remove(followeeID)
        followersByUserID[followeeID]?.remove(followerID)
        if followingByUserID[followerID]?.isEmpty == true {
            followingByUserID[followerID] = nil
        }
        if followersByUserID[followeeID]?.isEmpty == true {
            followersByUserID[followeeID] = nil
        }
        if followerID == currentUser.id {
            followingUserIDs.remove(followeeID)
        }
        rebuildFollowCounts()
        applyUserCountsFromFollowState(userID: followerID)
        applyUserCountsFromFollowState(userID: followeeID)
    }

    private func removeFollows(involving userIDs: Set<String>) {
        guard !userIDs.isEmpty else { return }

        var nextFollowingByUserID: [String: Set<String>] = [:]
        var nextFollowersByUserID: [String: Set<String>] = [:]

        for (followerID, followeeIDs) in followingByUserID where !userIDs.contains(followerID) {
            let filteredFollowees = followeeIDs.subtracting(userIDs)
            guard !filteredFollowees.isEmpty else { continue }

            nextFollowingByUserID[followerID] = filteredFollowees
            for followeeID in filteredFollowees {
                nextFollowersByUserID[followeeID, default: []].insert(followerID)
            }
        }

        followingByUserID = nextFollowingByUserID
        followersByUserID = nextFollowersByUserID
        followingUserIDs = followingByUserID[currentUser.id, default: []]
        rebuildFollowCounts()
    }

    private func rebuildFollowCounts() {
        followingCountsByUserID = followingByUserID.mapValues { $0.count }
        followerCountsByUserID = followersByUserID.mapValues { $0.count }
    }

    private func adjustShareCount(sourcePostID: String, shareType: PostShareType, amount: Int) {
        guard let index = posts.firstIndex(where: { $0.id == sourcePostID }) else { return }

        switch shareType {
        case .repost:
            posts[index].repostCount = max(posts[index].repostCount + amount, 0)
        case .quote:
            posts[index].quoteCount = max(posts[index].quoteCount + amount, 0)
        case .original:
            break
        }
    }

    private func adjustCommentCount(postID: String, amount: Int) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index].commentCount = max(posts[index].commentCount + amount, 0)
    }

    private func mergeDemoFollows(from seed: MockDataStore, activeCurrentUserID: String, seedCurrentUserID: String) {
        let knownUserIDs = Set(users.map(\.id))
        for (followerID, followeeIDs) in seed.followingByUserID {
            let mappedFollowerID = followerID == seedCurrentUserID ? activeCurrentUserID : followerID
            guard knownUserIDs.contains(mappedFollowerID) else { continue }

            for followeeID in followeeIDs {
                let mappedFolloweeID = followeeID == seedCurrentUserID ? activeCurrentUserID : followeeID
                guard knownUserIDs.contains(mappedFolloweeID) else { continue }
                addFollowLocally(followerID: mappedFollowerID, followeeID: mappedFolloweeID)
            }
        }
    }

    private func shouldSkipRemoteFollowWrite(for userID: String) -> Bool {
        isDemoDataVisible && MockDataStore().users.contains { $0.id == userID }
    }

    private var canCurrentUserCreateContent: Bool {
        !currentUser.isDeleted && !currentUser.isSuspended
    }

    private func containsMutedWord(_ post: Post) -> Bool {
        MutedWordNormalizer.containsMutedWord(in: post, mutedWords: mutedWords)
    }

    private func containsMutedWord(_ comment: Comment) -> Bool {
        MutedWordNormalizer.containsMutedWord(in: comment, mutedWords: mutedWords)
    }

    private func isVisiblePost(_ post: Post) -> Bool {
        guard !post.isDeleted else { return false }
        if currentUser.isAdmin { return true }
        return post.moderationStatus == .active
    }

    private func isVisibleComment(_ comment: Comment) -> Bool {
        guard !comment.isDeleted else { return false }
        if currentUser.isAdmin { return true }
        return comment.moderationStatus == .active
    }

    private func mostRecentPostDate(for userID: String) -> Date {
        posts
            .filter { $0.userId == userID && isVisiblePost($0) && !containsMutedWord($0) }
            .map(\.createdAt)
            .max() ?? Date.distantPast
    }

    private func preferredTopics() -> Set<String> {
        let ownTopics = posts
            .filter { $0.userId == currentUser.id && isVisiblePost($0) && !containsMutedWord($0) }
            .flatMap(\.topics)
        let followedTopics = posts
            .filter { followingUserIDs.contains($0.userId) && isVisiblePost($0) && !containsMutedWord($0) }
            .flatMap(\.topics)
        return Set(ownTopics + followedTopics)
    }

    private func recommendationScore(for post: Post) -> Double {
        let author = user(for: post.userId)
        let engagement = post.likeCount + post.commentCount * 2 + post.repostCount * 3 + post.quoteCount * 4
        let humanRateScore = (author?.humanVerifiedPostRate ?? 0) * 30
        let humanLevelScore = Double(author?.humanLevel ?? 1) * 4
        let engagementScore = log(Double(max(engagement, 0)) + 1) * 12
        let topicScore = Double(Set(post.topics).intersection(preferredTopics()).count) * 8
        let ageHours = max(Date().timeIntervalSince(post.createdAt) / 3600, 0)
        let recencyScore = max(0, 20 - min(ageHours, 72) / 72 * 20)
        let verifiedPostScore = post.humanBadge == .verified ? 8.0 : 0.0
        return humanRateScore + humanLevelScore + engagementScore + topicScore + recencyScore + verifiedPostScore
    }

    private func starterPackCandidates() -> [AppUser] {
        users.filter { user in
            user.id != currentUser.id
            && !user.isDeleted
            && !user.isSuspended
            && !followingUserIDs.contains(user.id)
            && !blockedUserIDs.contains(user.id)
            && !mutedUserIDs.contains(user.id)
            && user.humanVerifiedPostRate >= 0.75
            && postCount(for: user.id) > 0
            && followerCount(for: user.id) >= AppConstants.minimumStarterPackFollowerCount
        }
    }

    private func starterPackScore(for user: AppUser, category: StarterPackCategory) -> Double {
        userRecommendationScore(user) + (matchesStarterPackCategory(user, category: category) ? 40 : 0)
    }

    private func userRecommendationScore(_ user: AppUser) -> Double {
        let postActivity = Double(postCount(for: user.id)) * 3
        let followerScore = log(Double(max(followerCount(for: user.id), 0)) + 1) * 12
        let recencyScore = mostRecentPostDate(for: user.id) == .distantPast
            ? 0
            : max(0, 20 - min(Date().timeIntervalSince(mostRecentPostDate(for: user.id)) / 3600, 72) / 72 * 20)
        return user.humanVerifiedPostRate * 40 + Double(user.humanLevel) * 5 + followerScore + postActivity + recencyScore
    }

    private func matchesStarterPackCategory(_ user: AppUser, category: StarterPackCategory) -> Bool {
        let corpus = MutedWordNormalizer.normalize(
            ([user.displayName, user.handle, user.bio] + posts.filter { $0.userId == user.id }.map(\.body)).joined(separator: " ")
        )
        switch category {
        case .writers:
            return corpus.contains("言葉") || corpus.contains("文章") || corpus.contains("入力")
        case .daily:
            return corpus.contains("日常") || corpus.contains("日々") || corpus.contains("今日")
        case .creative:
            return corpus.contains("創作") || corpus.contains("作品") || corpus.contains("物語")
        case .learning:
            return corpus.contains("学び") || corpus.contains("学習") || corpus.contains("考え")
        }
    }

    private func refilterSearchResults() {
        topicSearchResults = topicSearchResults.filter { !containsMutedWord($0) }
        topicRoomSearchResults = topicRoomSearchResults.filter { room in
            !mutedWords.contains { mutedWord in
                MutedWordNormalizer.normalize([room.topic, room.title, room.description].joined(separator: " "))
                    .contains(mutedWord.normalizedWord)
            }
        }
        postSearchResults = postSearchResults.filter { !containsMutedWord($0) }
    }

    private func timelinePaginationCursorDate() -> Date? {
        let referencedPostIDs = Set(posts.compactMap(\.sourcePostID))
        let timelinePagePosts = posts.filter { !referencedPostIDs.contains($0.id) }
        return timelinePagePosts.map(\.createdAt).min()
    }

    private func applyUserCountsFromFollowState(userID: String) {
        guard let index = users.firstIndex(where: { $0.id == userID }) else { return }
        users[index].followerCount = followerCountsByUserID[userID, default: users[index].followerCount]
        users[index].followingCount = followingCountsByUserID[userID, default: users[index].followingCount]
        if currentUser.id == userID {
            currentUser = users[index]
        }
    }

    private func updateAdminReportLocally(_ reportID: String, status: String, adminNote: String) {
        let now = Date()
        for index in adminReports.indices where adminReports[index].id == reportID {
            adminReports[index].status = status
            adminReports[index].adminNote = adminNote.isEmpty ? nil : adminNote
            adminReports[index].resolvedAt = now
            adminReports[index].resolvedBy = currentUser.id
        }
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
                guard !seen.contains(post.id), isVisiblePost(post) else { return false }
                seen.insert(post.id)
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<String>()
        return comments.filter { comment in
            guard !seen.contains(comment.id), isVisibleComment(comment) else { return false }
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

private extension AppUser {
    func demoProfileCopy(currentUserID: String, appleUserID: String?) -> AppUser {
        AppUser(
            id: currentUserID,
            displayName: displayName,
            handle: handle,
            bio: bio,
            avatarUrl: avatarUrl,
            appleUserId: appleUserID,
            humanLevel: humanLevel,
            humanVerifiedPostRate: humanVerifiedPostRate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted,
            isAdmin: isAdmin,
            isSuspended: isSuspended,
            followerCount: followerCount,
            followingCount: followingCount
        )
    }
}

private extension Post {
    func replacingBody(_ body: String) -> Post {
        Post(
            id: id,
            userId: userId,
            body: body,
            topics: TopicExtractor.topics(in: body),
            searchTokens: PostSearchTokenizer.tokens(in: body, topics: TopicExtractor.topics(in: body)),
            mediaItems: mediaItems,
            shareType: shareType,
            sourcePostID: sourcePostID,
            sourceUserID: sourceUserID,
            commentPermission: commentPermission,
            humanScore: humanScore,
            humanBadge: humanBadge,
            inputDurationMs: inputDurationMs,
            characterCount: body.count,
            editCount: editCount + 1,
            deleteCount: deleteCount,
            suspiciousBulkInputCount: suspiciousBulkInputCount,
            appCheckVerified: appCheckVerified,
            likeCount: likeCount,
            commentCount: commentCount,
            repostCount: repostCount,
            quoteCount: quoteCount,
            createdAt: createdAt,
            updatedAt: Date(),
            isDeleted: isDeleted,
            moderationStatus: moderationStatus,
            hiddenReason: hiddenReason,
            hiddenAt: hiddenAt
        )
    }

    func demoCopy(currentUserID: String, seedCurrentUserID: String) -> Post {
        Post(
            id: "demo-\(id)",
            userId: userId == seedCurrentUserID ? currentUserID : userId,
            body: body,
            topics: topics,
            searchTokens: searchTokens,
            mediaItems: mediaItems,
            shareType: shareType,
            sourcePostID: sourcePostID.map { "demo-\($0)" },
            sourceUserID: sourceUserID == seedCurrentUserID ? currentUserID : sourceUserID,
            commentPermission: commentPermission,
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
            repostCount: repostCount,
            quoteCount: quoteCount,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isDeleted: isDeleted,
            moderationStatus: moderationStatus,
            hiddenReason: hiddenReason,
            hiddenAt: hiddenAt
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
            isDeleted: isDeleted,
            moderationStatus: moderationStatus,
            hiddenReason: hiddenReason,
            hiddenAt: hiddenAt
        )
    }
}
