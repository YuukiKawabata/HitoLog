import Combine
import Foundation

@MainActor
final class MockDataStore: ObservableObject {
    @Published private(set) var currentUser: AppUser
    @Published private(set) var users: [AppUser]
    @Published private(set) var posts: [Post]
    @Published private(set) var comments: [Comment]
    @Published private(set) var likedPostIDs: Set<String>
    @Published private(set) var blockedUserIDs: Set<String>
    @Published private(set) var mutedUserIDs: Set<String>
    @Published private(set) var reportHistory: [ReportRecord]

    private let initialCurrentUser: AppUser
    private let initialUsers: [AppUser]
    private let initialPosts: [Post]
    private let initialComments: [Comment]
    private let initialLikedPostIDs: Set<String>

    var recentPostCount: Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return posts.filter { $0.userId == currentUser.id && $0.createdAt >= oneHourAgo }.count
    }

    var verifiedPostRate: Double {
        guard !posts.isEmpty else { return 0 }
        let verifiedCount = posts.filter { $0.humanBadge == .verified }.count
        return Double(verifiedCount) / Double(posts.count)
    }

    var timelinePosts: [Post] {
        posts.filter { post in
            !blockedUserIDs.contains(post.userId) && !mutedUserIDs.contains(post.userId)
        }
    }

    var timelineVerifiedPostRate: Double {
        guard !timelinePosts.isEmpty else { return 0 }
        let verifiedCount = timelinePosts.filter { $0.humanBadge == .verified }.count
        return Double(verifiedCount) / Double(timelinePosts.count)
    }

    init() {
        let now = Date()
        let calendar = Calendar.current
        let currentUser = AppUser(
            id: "user-nagi",
            displayName: "Nagi",
            handle: "nagi_words",
            bio: "AI時代に、自分で考えて入力した言葉を残しています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.97,
            createdAt: calendar.date(byAdding: .day, value: -32, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let secondUser = AppUser(
            id: "user-aoi",
            displayName: "Aoi",
            handle: "aoi_note",
            bio: "夜に少しだけ、考えたことを書き残します。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 5,
            humanVerifiedPostRate: 0.99,
            createdAt: calendar.date(byAdding: .day, value: -118, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let thirdUser = AppUser(
            id: "user-ren",
            displayName: "Ren",
            handle: "ren_thinks",
            bio: "速さより、自分で考えた言葉を大事にしています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.94,
            createdAt: calendar.date(byAdding: .day, value: -76, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let fourthUser = AppUser(
            id: "user-mio",
            displayName: "Mio",
            handle: "mio_daily",
            bio: "日々の小さな違和感や発見を短く書きます。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 3,
            humanVerifiedPostRate: 0.91,
            createdAt: calendar.date(byAdding: .day, value: -44, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let fifthUser = AppUser(
            id: "user-haru",
            displayName: "Haru",
            handle: "haru_log",
            bio: "SNSをゆっくり使いたい人です。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 3,
            humanVerifiedPostRate: 0.89,
            createdAt: calendar.date(byAdding: .day, value: -21, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let post1Body = "AIが文章をすぐ作れる時代だからこそ、少し迷いながら自分で入力した言葉を残しておきたい。今日はその一文だけで十分。"
        let post2Body = "貼り付けではなく、その場で考えながら打った言葉には、その人の温度が残る気がする。HitoLogはその小さな跡を大切にしたい。"
        let post3Body = "速く投稿するより、自分の言葉になるまで少し待つ。AIのきれいな文章より、今の自分にしか書けない違和感を残したい。"
        let post4Body = "今日はうまく言えない気持ちを、そのまま書いた。整っていない文章でも、自分で入力した跡があると少し安心する。"
        let post5Body = "SNSを開くたびに急かされる感じが苦手だった。ここでは短くても、自分で打った言葉だけをゆっくり読めるのがいい。"
        let post6Body = "コメントも短くていい。読んだ人が、自分の言葉で返してくれるだけで十分うれしい。"

        let users = [currentUser, secondUser, thirdUser, fourthUser, fifthUser]
        let posts = [
            Post(
                id: "post-1",
                userId: secondUser.id,
                body: post1Body,
                humanScore: 96,
                humanBadge: .verified,
                inputDurationMs: 74_000,
                characterCount: post1Body.count,
                editCount: 12,
                deleteCount: 5,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 34,
                commentCount: 2,
                createdAt: now.addingTimeInterval(-240),
                updatedAt: now.addingTimeInterval(-240),
                isDeleted: false
            ),
            Post(
                id: "post-2",
                userId: currentUser.id,
                body: post2Body,
                humanScore: 94,
                humanBadge: .verified,
                inputDurationMs: 82_000,
                characterCount: post2Body.count,
                editCount: 15,
                deleteCount: 6,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 28,
                commentCount: 3,
                createdAt: now.addingTimeInterval(-1_100),
                updatedAt: now.addingTimeInterval(-1_100),
                isDeleted: false
            ),
            Post(
                id: "post-3",
                userId: thirdUser.id,
                body: post3Body,
                humanScore: 92,
                humanBadge: .verified,
                inputDurationMs: 69_000,
                characterCount: post3Body.count,
                editCount: 10,
                deleteCount: 4,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 21,
                commentCount: 1,
                createdAt: now.addingTimeInterval(-3_600),
                updatedAt: now.addingTimeInterval(-3_600),
                isDeleted: false
            ),
            Post(
                id: "post-4",
                userId: fourthUser.id,
                body: post4Body,
                humanScore: 95,
                humanBadge: .verified,
                inputDurationMs: 91_000,
                characterCount: post4Body.count,
                editCount: 18,
                deleteCount: 8,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 26,
                commentCount: 1,
                createdAt: now.addingTimeInterval(-6_800),
                updatedAt: now.addingTimeInterval(-6_800),
                isDeleted: false
            ),
            Post(
                id: "post-5",
                userId: fifthUser.id,
                body: post5Body,
                humanScore: 88,
                humanBadge: .verified,
                inputDurationMs: 58_000,
                characterCount: post5Body.count,
                editCount: 9,
                deleteCount: 3,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 17,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-10_400),
                updatedAt: now.addingTimeInterval(-10_400),
                isDeleted: false
            ),
            Post(
                id: "post-6",
                userId: currentUser.id,
                body: post6Body,
                humanScore: 79,
                humanBadge: .checking,
                inputDurationMs: 33_000,
                characterCount: post6Body.count,
                editCount: 4,
                deleteCount: 1,
                suspiciousBulkInputCount: 1,
                appCheckVerified: true,
                likeCount: 12,
                commentCount: 1,
                createdAt: now.addingTimeInterval(-15_200),
                updatedAt: now.addingTimeInterval(-15_200),
                isDeleted: false
            )
        ]
        let comments = [
            Comment(
                id: "comment-1",
                postId: "post-1",
                userId: currentUser.id,
                body: "この感覚わかります。整いすぎていない言葉のほうが、あとで読み返したくなります。",
                humanScore: 93,
                createdAt: now.addingTimeInterval(-210),
                updatedAt: now.addingTimeInterval(-210),
                isDeleted: false
            ),
            Comment(
                id: "comment-2",
                postId: "post-1",
                userId: fifthUser.id,
                body: "本人入力バッジがあると、読む前の安心感が少し変わりますね。",
                humanScore: 89,
                createdAt: now.addingTimeInterval(-180),
                updatedAt: now.addingTimeInterval(-180),
                isDeleted: false
            ),
            Comment(
                id: "comment-3",
                postId: "post-2",
                userId: secondUser.id,
                body: "HitoLogらしさが一番伝わる言葉だと思います。",
                humanScore: 96,
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-900),
                isDeleted: false
            ),
            Comment(
                id: "comment-4",
                postId: "post-2",
                userId: thirdUser.id,
                body: "コピペ禁止というより、本人の入力を大切にする感じがいいですね。",
                humanScore: 91,
                createdAt: now.addingTimeInterval(-760),
                updatedAt: now.addingTimeInterval(-760),
                isDeleted: false
            ),
            Comment(
                id: "comment-5",
                postId: "post-2",
                userId: fourthUser.id,
                body: "AI時代のSNSとして、最初に伝える価値がはっきりしています。",
                humanScore: 92,
                createdAt: now.addingTimeInterval(-610),
                updatedAt: now.addingTimeInterval(-610),
                isDeleted: false
            ),
            Comment(
                id: "comment-6",
                postId: "post-3",
                userId: fifthUser.id,
                body: "速さを競わない場所、ちょうど欲しかったです。",
                humanScore: 88,
                createdAt: now.addingTimeInterval(-3_100),
                updatedAt: now.addingTimeInterval(-3_100),
                isDeleted: false
            ),
            Comment(
                id: "comment-7",
                postId: "post-4",
                userId: secondUser.id,
                body: "そのまま残せる場所があるだけで、書くハードルが下がります。",
                humanScore: 94,
                createdAt: now.addingTimeInterval(-6_200),
                updatedAt: now.addingTimeInterval(-6_200),
                isDeleted: false
            ),
            Comment(
                id: "comment-8",
                postId: "post-6",
                userId: thirdUser.id,
                body: "短いコメントでも、本人の言葉だとちゃんと届きますね。",
                humanScore: 90,
                createdAt: now.addingTimeInterval(-14_600),
                updatedAt: now.addingTimeInterval(-14_600),
                isDeleted: false
            )
        ]
        self.initialCurrentUser = currentUser
        self.initialUsers = users
        self.initialPosts = posts
        self.initialComments = comments
        self.initialLikedPostIDs = ["post-1", "post-5"]

        self.currentUser = currentUser
        self.users = users
        self.posts = posts
        self.comments = comments
        self.likedPostIDs = ["post-1", "post-5"]
        self.blockedUserIDs = []
        self.mutedUserIDs = []
        self.reportHistory = [
            ReportRecord(
                id: "report-1",
                targetDescription: "@sample_spam の投稿",
                reason: "spam",
                createdAt: now.addingTimeInterval(-86_400),
                status: "対応済み"
            )
        ]
    }

    func user(for id: String) -> AppUser? {
        users.first { $0.id == id }
    }

    func post(for id: String) -> Post? {
        posts.first { $0.id == id }
    }

    func insert(_ post: Post) {
        posts.insert(post, at: 0)
    }

    func updateCurrentUser(displayName: String, handle: String, bio: String) {
        currentUser.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.handle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUser.updatedAt = Date()

        if let index = users.firstIndex(where: { $0.id == currentUser.id }) {
            users[index] = currentUser
        }
    }

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }

        if likedPostIDs.contains(postID) {
            likedPostIDs.remove(postID)
            posts[index].likeCount = max(posts[index].likeCount - 1, 0)
        } else {
            likedPostIDs.insert(postID)
            posts[index].likeCount += 1
        }
    }

    func comments(for postID: String) -> [Comment] {
        comments
            .filter { $0.postId == postID && !$0.isDeleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(body: String, to postID: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return }

        let now = Date()
        comments.append(
            Comment(
                id: UUID().uuidString,
                postId: postID,
                userId: currentUser.id,
                body: trimmedBody,
                humanScore: 88,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
        )

        if let index = posts.firstIndex(where: { $0.id == postID }) {
            posts[index].commentCount += 1
        }
    }

    func postCount(for userID: String) -> Int {
        posts.filter { $0.userId == userID }.count
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
    }

    func unblock(_ userID: String) {
        blockedUserIDs.remove(userID)
    }

    func mute(_ userID: String) {
        guard userID != currentUser.id else { return }
        mutedUserIDs.insert(userID)
    }

    func unmute(_ userID: String) {
        mutedUserIDs.remove(userID)
    }

    func addReport(targetDescription: String, reason: String) {
        reportHistory.insert(
            ReportRecord(
                id: UUID().uuidString,
                targetDescription: targetDescription,
                reason: reason,
                createdAt: Date(),
                status: "確認待ち"
            ),
            at: 0
        )
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
    }

    func refresh() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
    }
}

struct ReportRecord: Identifiable, Codable, Equatable {
    let id: String
    let targetDescription: String
    let reason: String
    let createdAt: Date
    var status: String
}
