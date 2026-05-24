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
        let currentUser = AppUser(
            id: "user-yuuki",
            displayName: "Yuuki",
            handle: "kakabata",
            bio: "AI時代に、自分の言葉を残すSNSを作っています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.98,
            createdAt: Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let secondUser = AppUser(
            id: "user-mio",
            displayName: "Mio",
            handle: "mio_words",
            bio: "日々の考えを短く残しています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 3,
            humanVerifiedPostRate: 0.91,
            createdAt: Calendar.current.date(byAdding: .day, value: -40, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let thirdUser = AppUser(
            id: "user-riku",
            displayName: "Riku",
            handle: "riku_notes",
            bio: "プロダクトの手触りを観察しています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 2,
            humanVerifiedPostRate: 0.86,
            createdAt: Calendar.current.date(byAdding: .day, value: -9, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let fourthUser = AppUser(
            id: "user-sana",
            displayName: "Sana",
            handle: "sana_daily",
            bio: "考えごとをゆっくり書きます。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 5,
            humanVerifiedPostRate: 0.99,
            createdAt: Calendar.current.date(byAdding: .day, value: -120, to: now) ?? now,
            updatedAt: now,
            isDeleted: false
        )

        let users = [currentUser, secondUser, thirdUser, fourthUser]
        let posts = [
            Post(
                id: "post-1",
                userId: currentUser.id,
                body: "今日は朝散歩しながら、アプリのことを考えていた。自分の言葉で投稿するSNS、意外と需要ありそう。",
                humanScore: 92,
                humanBadge: .verified,
                inputDurationMs: 42_000,
                characterCount: 52,
                editCount: 8,
                deleteCount: 3,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 12,
                commentCount: 2,
                createdAt: now.addingTimeInterval(-300),
                updatedAt: now.addingTimeInterval(-300),
                isDeleted: false
            ),
            Post(
                id: "post-2",
                userId: secondUser.id,
                body: "短い言葉でも、手で入力した跡が残ると読み方が変わる気がする。",
                humanScore: 88,
                humanBadge: .verified,
                inputDurationMs: 31_000,
                characterCount: 31,
                editCount: 5,
                deleteCount: 1,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 7,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-1600),
                updatedAt: now.addingTimeInterval(-1600),
                isDeleted: false
            ),
            Post(
                id: "post-3",
                userId: fourthUser.id,
                body: "下書きから貼るのではなく、その場で考えながら書くと、文章に迷いが残る。その迷いまで読める場所にしたい。",
                humanScore: 95,
                humanBadge: .verified,
                inputDurationMs: 68_000,
                characterCount: 55,
                editCount: 13,
                deleteCount: 6,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 28,
                commentCount: 1,
                createdAt: now.addingTimeInterval(-4_900),
                updatedAt: now.addingTimeInterval(-4_900),
                isDeleted: false
            ),
            Post(
                id: "post-4",
                userId: thirdUser.id,
                body: "Human Scoreは点数を見せるより、読む側に小さな安心感だけ渡すほうがよさそう。見せすぎると攻略ゲームになる。",
                humanScore: 76,
                humanBadge: .checking,
                inputDurationMs: 24_000,
                characterCount: 57,
                editCount: 2,
                deleteCount: 0,
                suspiciousBulkInputCount: 1,
                appCheckVerified: true,
                likeCount: 9,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-7_200),
                isDeleted: false
            ),
            Post(
                id: "post-5",
                userId: currentUser.id,
                body: "MVPは小さくていい。ただ、最初の投稿画面だけは思想が伝わる品質にしたい。",
                humanScore: 90,
                humanBadge: .verified,
                inputDurationMs: 39_000,
                characterCount: 38,
                editCount: 7,
                deleteCount: 2,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 18,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-12_800),
                updatedAt: now.addingTimeInterval(-12_800),
                isDeleted: false
            )
        ]
        let comments = [
            Comment(
                id: "comment-1",
                postId: "post-1",
                userId: secondUser.id,
                body: "この方向性、読み手にも書き手にも効きそうです。",
                humanScore: 87,
                createdAt: now.addingTimeInterval(-260),
                updatedAt: now.addingTimeInterval(-260),
                isDeleted: false
            ),
            Comment(
                id: "comment-2",
                postId: "post-1",
                userId: fourthUser.id,
                body: "コピペ禁止より、本人入力という言い方のほうが好き。",
                humanScore: 94,
                createdAt: now.addingTimeInterval(-220),
                updatedAt: now.addingTimeInterval(-220),
                isDeleted: false
            ),
            Comment(
                id: "comment-3",
                postId: "post-3",
                userId: currentUser.id,
                body: "その迷いを消さない設計にしたいですね。",
                humanScore: 92,
                createdAt: now.addingTimeInterval(-4_600),
                updatedAt: now.addingTimeInterval(-4_600),
                isDeleted: false
            )
        ]
        self.initialCurrentUser = currentUser
        self.initialUsers = users
        self.initialPosts = posts
        self.initialComments = comments
        self.initialLikedPostIDs = ["post-2"]

        self.currentUser = currentUser
        self.users = users
        self.posts = posts
        self.comments = comments
        self.likedPostIDs = ["post-2"]
        self.blockedUserIDs = [thirdUser.id]
        self.mutedUserIDs = []
        self.reportHistory = [
            ReportRecord(
                id: "report-1",
                targetDescription: "@riku_notes の投稿",
                reason: "spam",
                createdAt: now.addingTimeInterval(-86_400),
                status: "確認待ち"
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
