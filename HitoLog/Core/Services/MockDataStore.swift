import Combine
import Foundation

@MainActor
final class MockDataStore: ObservableObject {
    @Published private(set) var currentUser: AppUser
    @Published private(set) var users: [AppUser]
    @Published private(set) var posts: [Post]
    @Published private(set) var articles: [Article]
    @Published private(set) var comments: [Comment]
    @Published private(set) var likedPostIDs: Set<String>
    @Published private(set) var blockedUserIDs: Set<String>
    @Published private(set) var mutedUserIDs: Set<String>
    @Published private(set) var followingUserIDs: Set<String>
    @Published private(set) var followerCountsByUserID: [String: Int]
    @Published private(set) var followingCountsByUserID: [String: Int]
    @Published private(set) var followersByUserID: [String: Set<String>]
    @Published private(set) var followingByUserID: [String: Set<String>]
    @Published private(set) var reportHistory: [ReportRecord]

    private let initialCurrentUser: AppUser
    private let initialUsers: [AppUser]
    private let initialPosts: [Post]
    private let initialArticles: [Article]
    private let initialComments: [Comment]
    private let initialLikedPostIDs: Set<String>
    private let initialFollowingUserIDs: Set<String>
    private let initialFollowerCountsByUserID: [String: Int]
    private let initialFollowingCountsByUserID: [String: Int]
    private let initialFollowersByUserID: [String: Set<String>]
    private let initialFollowingByUserID: [String: Set<String>]

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
            !post.isDeleted
            && post.moderationStatus == .active
            && post.userId != currentUser.id
            && !blockedUserIDs.contains(post.userId)
            && !mutedUserIDs.contains(post.userId)
        }
    }

    var followingTimelinePosts: [Post] {
        timelinePosts.filter { post in
            followingUserIDs.contains(post.userId)
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
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: now) ?? now
        }

        let currentUser = AppUser(
            id: "user-nagi",
            displayName: "Nagi",
            handle: "nagi_words",
            bio: "AI時代に、自分で考えて入力した言葉を残しています。短くても、その日の自分の温度を。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.97,
            createdAt: daysAgo(32),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: "nagi-words.example.com",
            location: "京都",
            occupation: "言葉を書く人 / エッセイ"
        )

        let secondUser = AppUser(
            id: "user-aoi",
            displayName: "Aoi",
            handle: "aoi_note",
            bio: "夜に少しだけ、考えたことを書き残します。エッセイと、読んだ本のこと。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 5,
            humanVerifiedPostRate: 0.99,
            createdAt: daysAgo(118),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: "aoi-essay.example.com",
            location: "東京",
            occupation: "エッセイスト"
        )

        let thirdUser = AppUser(
            id: "user-ren",
            displayName: "Ren",
            handle: "ren_thinks",
            bio: "速さより、自分で考えた言葉を大事にしています。本づくりの仕事をしています。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.94,
            createdAt: daysAgo(76),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: nil,
            location: "福岡",
            occupation: "編集者"
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
            createdAt: daysAgo(44),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: nil,
            location: "札幌",
            occupation: "会社員 / 日記"
        )

        let fifthUser = AppUser(
            id: "user-haru",
            displayName: "Haru",
            handle: "haru_log",
            bio: "SNSをゆっくり使いたい人です。大学で言語学を勉強中。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 3,
            humanVerifiedPostRate: 0.89,
            createdAt: daysAgo(21),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: nil,
            location: "名古屋",
            occupation: "大学生"
        )

        let sixthUser = AppUser(
            id: "user-sora",
            displayName: "Sora",
            handle: "sora_draws",
            bio: "絵と言葉のあいだを行き来しています。ラフのような文章が好き。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 4,
            humanVerifiedPostRate: 0.93,
            createdAt: daysAgo(64),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: "sora-art.example.com",
            location: "大阪",
            occupation: "イラストレーター"
        )

        let seventhUser = AppUser(
            id: "user-yuki",
            displayName: "Yuki",
            handle: "yuki_coffee",
            bio: "小さな珈琲店をやっています。開店前の十五分だけ書く人。",
            avatarUrl: nil,
            appleUserId: nil,
            humanLevel: 5,
            humanVerifiedPostRate: 0.96,
            createdAt: daysAgo(150),
            updatedAt: now,
            isDeleted: false,
            followerCount: 0,
            followingCount: 0,
            website: nil,
            location: "神戸",
            occupation: "珈琲店主"
        )

        let users = [
            currentUser, secondUser, thirdUser, fourthUser,
            fifthUser, sixthUser, seventhUser
        ]

        // 本文末尾のハッシュタグから topics が自動抽出され、話題ルームに集計される
        let post1Body = "AIが文章をすぐ作れる時代だからこそ、少し迷いながら自分で入力した言葉を残しておきたい。今日はその一文だけで十分。 #言葉"
        let post2Body = "貼り付けではなく、その場で考えながら打った言葉には、その人の温度が残る気がする。HitoLogはその小さな跡を大切にしたい。 #言葉 #創作"
        let post3Body = "速く投稿するより、自分の言葉になるまで少し待つ。AIのきれいな文章より、今の自分にしか書けない違和感を残したい。 #学び"
        let post4Body = "今日はうまく言えない気持ちを、そのまま書いた。整っていない文章でも、自分で入力した跡があると少し安心する。 #日常ログ"
        let post5Body = "SNSを開くたびに急かされる感じが苦手だった。ここでは短くても、自分で打った言葉だけをゆっくり読めるのがいい。 #日常ログ"
        let post6Body = "コメントも短くていい。読んだ人が、自分の言葉で返してくれるだけで十分うれしい。 #言葉"
        let post7Body = "ラフを描くみたいに、まず下手でもいいから書いてみる。あとで整える前の言葉が、いちばん自分らしいと思う。 #創作 #言葉"
        let post8Body = "朝、店を開ける前の十五分だけ、その日の一杯について書く。淹れた数だけ、言葉も静かに増えていく。 #日常ログ #コーヒー"
        let post9Body = "読み終えた本のことを、要約ではなく自分の感想で残す。誰かの言葉の借り物にはしたくないから。 #読書 #学び"
        let post10Body = "編集をしていると、整いすぎた文章の奥にある『その人の癖』が恋しくなる。ここではそれが読める気がする。 #言葉"
        let quote12Body = "これ、すごく分かる。整えるほど消えていくものがあるんだよな。 #創作"

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
                repostCount: 1,
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
            ),
            Post(
                id: "post-7",
                userId: sixthUser.id,
                body: post7Body,
                humanScore: 90,
                humanBadge: .verified,
                inputDurationMs: 65_000,
                characterCount: post7Body.count,
                editCount: 11,
                deleteCount: 5,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 19,
                commentCount: 1,
                createdAt: now.addingTimeInterval(-20_000),
                updatedAt: now.addingTimeInterval(-20_000),
                isDeleted: false
            ),
            Post(
                id: "post-8",
                userId: seventhUser.id,
                body: post8Body,
                humanScore: 93,
                humanBadge: .verified,
                inputDurationMs: 71_000,
                characterCount: post8Body.count,
                editCount: 13,
                deleteCount: 4,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 23,
                commentCount: 2,
                createdAt: now.addingTimeInterval(-28_800),
                updatedAt: now.addingTimeInterval(-28_800),
                isDeleted: false
            ),
            Post(
                id: "post-9",
                userId: secondUser.id,
                body: post9Body,
                humanScore: 91,
                humanBadge: .verified,
                inputDurationMs: 60_000,
                characterCount: post9Body.count,
                editCount: 9,
                deleteCount: 3,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 15,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-43_200),
                updatedAt: now.addingTimeInterval(-43_200),
                isDeleted: false
            ),
            Post(
                id: "post-10",
                userId: thirdUser.id,
                body: post10Body,
                humanScore: 97,
                humanBadge: .verified,
                inputDurationMs: 88_000,
                characterCount: post10Body.count,
                editCount: 16,
                deleteCount: 7,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 30,
                commentCount: 1,
                quoteCount: 1,
                createdAt: now.addingTimeInterval(-54_000),
                updatedAt: now.addingTimeInterval(-54_000),
                isDeleted: false
            ),
            // リポスト: Nagi が Aoi の post-1 をそのまま広める
            Post(
                id: "post-11",
                userId: currentUser.id,
                body: "",
                topics: ["言葉"],
                shareType: .repost,
                sourcePostID: "post-1",
                sourceUserID: secondUser.id,
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
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-7_200),
                isDeleted: false
            ),
            // 引用: Sora が Ren の post-10 に言葉を添える
            Post(
                id: "post-12",
                userId: sixthUser.id,
                body: quote12Body,
                shareType: .quote,
                sourcePostID: "post-10",
                sourceUserID: thirdUser.id,
                humanScore: 89,
                humanBadge: .verified,
                inputDurationMs: 41_000,
                characterCount: quote12Body.count,
                editCount: 7,
                deleteCount: 2,
                suspiciousBulkInputCount: 0,
                appCheckVerified: true,
                likeCount: 11,
                commentCount: 0,
                createdAt: now.addingTimeInterval(-50_000),
                updatedAt: now.addingTimeInterval(-50_000),
                isDeleted: false
            )
        ]

        let article1Preview = """
        夜になると、昼間は言えなかった言葉が少しずつ戻ってくる。
        誰に見せるためでもなく、ただ自分のために書く時間のこと。
        この記事では、わたしが夜だけ書くようになった理由と、続けるための小さな習慣を綴ります。
        """
        let article2Preview = """
        速く書ける時代に、あえて速く書かないという選択について。
        推敲を重ねることは効率の敵のように見えて、実は「自分の言葉」を守る最後の砦だと思っています。
        """
        let article3Preview = """
        AIがいくらでも文章を出力できるいま、手で打つことの意味はどこにあるのか。
        三十二日間、毎日この問いと向き合いながら書いてきた記録をまとめました。
        """
        let article4Preview = """
        札幌の冬は長い。だからこそ、毎日の小さなメモが積もると景色になる。
        今日はその書き方のコツを、ゆるくシェアします。
        """

        let articles = [
            Article(
                id: "article-1",
                userID: secondUser.id,
                title: "夜にだけ書ける言葉について",
                freePreviewBody: article1Preview,
                status: .published,
                price: .yen300,
                topics: ["言葉", "創作"],
                commentPermission: .everyone,
                humanBadge: .verified,
                humanScore: 95,
                inputDurationMs: 540_000,
                editCount: 42,
                deleteCount: 13,
                commentCount: 3,
                purchaseCount: 18,
                bookmarkCount: 24,
                createdAt: daysAgo(2),
                updatedAt: daysAgo(2)
            ),
            Article(
                id: "article-2",
                userID: thirdUser.id,
                title: "速く書かない、という技術",
                freePreviewBody: article2Preview,
                status: .published,
                price: .free,
                topics: ["学び", "言葉"],
                commentPermission: .everyone,
                humanBadge: .verified,
                humanScore: 96,
                inputDurationMs: 420_000,
                editCount: 35,
                deleteCount: 10,
                commentCount: 5,
                purchaseCount: 0,
                bookmarkCount: 31,
                createdAt: daysAgo(5),
                updatedAt: daysAgo(5)
            ),
            Article(
                id: "article-3",
                userID: currentUser.id,
                title: "AI時代に、手で書く意味",
                freePreviewBody: article3Preview,
                status: .published,
                price: .yen500,
                topics: ["言葉", "学び"],
                commentPermission: .everyone,
                humanBadge: .verified,
                humanScore: 94,
                inputDurationMs: 600_000,
                editCount: 48,
                deleteCount: 15,
                commentCount: 2,
                purchaseCount: 9,
                bookmarkCount: 14,
                createdAt: daysAgo(1),
                updatedAt: daysAgo(1)
            ),
            Article(
                id: "article-4",
                userID: fourthUser.id,
                title: "札幌の冬、毎日のメモ",
                freePreviewBody: article4Preview,
                status: .published,
                price: .free,
                topics: ["日常ログ"],
                commentPermission: .everyone,
                humanBadge: .checking,
                humanScore: 88,
                inputDurationMs: 300_000,
                editCount: 22,
                deleteCount: 6,
                commentCount: 1,
                purchaseCount: 0,
                bookmarkCount: 8,
                createdAt: daysAgo(3),
                updatedAt: daysAgo(3)
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
            ),
            Comment(
                id: "comment-9",
                postId: "post-7",
                userId: currentUser.id,
                body: "下書きのような言葉、わたしも好きです。整える前のほうが正直ですよね。",
                humanScore: 92,
                createdAt: now.addingTimeInterval(-19_000),
                updatedAt: now.addingTimeInterval(-19_000),
                isDeleted: false
            ),
            Comment(
                id: "comment-10",
                postId: "post-8",
                userId: fifthUser.id,
                body: "開店前の十五分、想像しただけで気持ちのいい時間です。",
                humanScore: 87,
                createdAt: now.addingTimeInterval(-27_000),
                updatedAt: now.addingTimeInterval(-27_000),
                isDeleted: false
            ),
            Comment(
                id: "comment-11",
                postId: "post-8",
                userId: secondUser.id,
                body: "淹れた数だけ言葉が増える、という表現が好きです。",
                humanScore: 95,
                createdAt: now.addingTimeInterval(-26_000),
                updatedAt: now.addingTimeInterval(-26_000),
                isDeleted: false
            )
        ]

        self.initialCurrentUser = currentUser
        self.initialUsers = users
        self.initialPosts = posts
        self.initialArticles = articles
        self.initialComments = comments
        self.initialLikedPostIDs = ["post-1", "post-5", "post-8"]
        let initialFollowingByUserID: [String: Set<String>] = [
            currentUser.id: [secondUser.id, thirdUser.id, sixthUser.id],
            secondUser.id: [currentUser.id, fourthUser.id, seventhUser.id],
            thirdUser.id: [fifthUser.id, sixthUser.id],
            fourthUser.id: [currentUser.id],
            sixthUser.id: [currentUser.id, thirdUser.id],
            seventhUser.id: [secondUser.id]
        ]
        let initialFollowersByUserID = Self.followersByUserID(from: initialFollowingByUserID)
        self.initialFollowingUserIDs = initialFollowingByUserID[currentUser.id, default: []]
        self.initialFollowerCountsByUserID = initialFollowersByUserID.mapValues { $0.count }
        self.initialFollowingCountsByUserID = initialFollowingByUserID.mapValues { $0.count }
        self.initialFollowersByUserID = initialFollowersByUserID
        self.initialFollowingByUserID = initialFollowingByUserID

        self.currentUser = currentUser
        self.users = users
        self.posts = posts
        self.articles = articles
        self.comments = comments
        self.likedPostIDs = ["post-1", "post-5", "post-8"]
        self.blockedUserIDs = []
        self.mutedUserIDs = []
        self.followingUserIDs = self.initialFollowingUserIDs
        self.followerCountsByUserID = self.initialFollowerCountsByUserID
        self.followingCountsByUserID = self.initialFollowingCountsByUserID
        self.followersByUserID = initialFollowersByUserID
        self.followingByUserID = initialFollowingByUserID
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
        posts.first { $0.id == id && !$0.isDeleted && $0.moderationStatus == .active }
    }

    func insert(_ post: Post) {
        guard !currentUser.isSuspended else { return }
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
        guard !currentUser.isSuspended,
              let index = posts.firstIndex(where: { $0.id == postID && $0.moderationStatus == .active }) else { return }

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
            .filter { $0.postId == postID && !$0.isDeleted && $0.moderationStatus == .active }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(body: String, to postID: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentUser.isSuspended, !trimmedBody.isEmpty, post(for: postID) != nil else { return }

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
        posts.filter { $0.userId == userID && !$0.isDeleted && $0.moderationStatus == .active }.count
    }

    func isFollowing(_ userID: String) -> Bool {
        followingUserIDs.contains(userID)
    }

    func followerCount(for userID: String) -> Int {
        followerCountsByUserID[userID, default: 0]
    }

    func followingCount(for userID: String) -> Int {
        followingCountsByUserID[userID, default: 0]
    }

    func followers(for userID: String) -> [AppUser] {
        sortedUsers(for: followersByUserID[userID, default: []])
    }

    func following(for userID: String) -> [AppUser] {
        sortedUsers(for: followingByUserID[userID, default: []])
    }

    func toggleFollow(userID: String) {
        guard userID != currentUser.id,
              user(for: userID) != nil,
              !blockedUserIDs.contains(userID) else {
            return
        }

        if followingUserIDs.contains(userID) {
            removeFollowLocally(followerID: currentUser.id, followeeID: userID)
        } else {
            addFollowLocally(followerID: currentUser.id, followeeID: userID)
        }
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
        removeFollowLocally(followerID: currentUser.id, followeeID: userID)
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
        articles = initialArticles
        comments = initialComments
        likedPostIDs = initialLikedPostIDs
        blockedUserIDs = []
        mutedUserIDs = []
        followingUserIDs = initialFollowingUserIDs
        followerCountsByUserID = initialFollowerCountsByUserID
        followingCountsByUserID = initialFollowingCountsByUserID
        followersByUserID = initialFollowersByUserID
        followingByUserID = initialFollowingByUserID
        reportHistory = []
    }

    func refresh() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
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
    }

    private func rebuildFollowCounts() {
        followingCountsByUserID = followingByUserID.mapValues { $0.count }
        followerCountsByUserID = followersByUserID.mapValues { $0.count }
    }

    private static func followersByUserID(from followingByUserID: [String: Set<String>]) -> [String: Set<String>] {
        var followersByUserID: [String: Set<String>] = [:]
        for (followerID, followeeIDs) in followingByUserID {
            for followeeID in followeeIDs {
                followersByUserID[followeeID, default: []].insert(followerID)
            }
        }
        return followersByUserID
    }
}

struct ReportRecord: Identifiable, Codable, Equatable {
    let id: String
    let targetDescription: String
    let reason: String
    let createdAt: Date
    var status: String
    var reporterID: String? = nil
    var targetType: ReportTargetType = .user
    var targetID: String? = nil
    var targetOwnerID: String? = nil
    var adminNote: String? = nil
    var resolvedAt: Date? = nil
    var resolvedBy: String? = nil
}

enum ReportTargetType: String, Codable, Equatable, CaseIterable {
    case post
    case comment
    case user
    case article
    case other

    var displayText: String {
        switch self {
        case .post:    return "投稿"
        case .comment: return "コメント"
        case .user:    return "ユーザー"
        case .article: return "記事"
        case .other:   return "その他"
        }
    }
}
