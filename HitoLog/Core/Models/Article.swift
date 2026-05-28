import Foundation

enum ArticlePrice: String, Codable, CaseIterable {
    case free
    case yen100
    case yen300
    case yen500
    case yen800
    case yen1000

    var displayText: String {
        switch self {
        case .free: return "無料"
        case .yen100: return "100円"
        case .yen300: return "300円"
        case .yen500: return "500円"
        case .yen800: return "800円"
        case .yen1000: return "1,000円"
        }
    }

    var iapProductID: String? {
        switch self {
        case .free: return nil
        case .yen100: return "jp.hitolog.article_unlock_100"
        case .yen300: return "jp.hitolog.article_unlock_300"
        case .yen500: return "jp.hitolog.article_unlock_500"
        case .yen800: return "jp.hitolog.article_unlock_800"
        case .yen1000: return "jp.hitolog.article_unlock_1000"
        }
    }

    var isPaid: Bool { self != .free }

    var priceInYen: Int {
        switch self {
        case .free:    return 0
        case .yen100:  return 100
        case .yen300:  return 300
        case .yen500:  return 500
        case .yen800:  return 800
        case .yen1000: return 1000
        }
    }
}

enum ArticleStatus: String, Codable {
    case draft
    case published
    case unpublished
    case underReview
}

struct Article: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    var title: String
    var freePreviewBody: String
    var status: ArticleStatus
    var price: ArticlePrice
    var topics: [String]
    var searchTokens: [String]
    var commentPermission: CommentPermission
    let humanBadge: HumanBadge
    let humanScore: Int
    let inputDurationMs: Int
    let editCount: Int
    let deleteCount: Int
    var commentCount: Int
    var purchaseCount: Int
    var bookmarkCount: Int
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var moderationStatus: ModerationStatus
    var hiddenReason: String?
    var hiddenAt: Date?

    init(
        id: String,
        userID: String,
        title: String,
        freePreviewBody: String,
        status: ArticleStatus = .draft,
        price: ArticlePrice = .free,
        topics: [String]? = nil,
        searchTokens: [String]? = nil,
        commentPermission: CommentPermission = .everyone,
        humanBadge: HumanBadge,
        humanScore: Int,
        inputDurationMs: Int,
        editCount: Int,
        deleteCount: Int,
        commentCount: Int = 0,
        purchaseCount: Int = 0,
        bookmarkCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool = false,
        moderationStatus: ModerationStatus = .active,
        hiddenReason: String? = nil,
        hiddenAt: Date? = nil
    ) {
        self.id = id
        self.userID = userID
        self.title = title
        self.freePreviewBody = freePreviewBody
        self.status = status
        self.price = price
        let combined = "\(title) \(freePreviewBody)"
        self.topics = topics ?? TopicExtractor.topics(in: combined)
        self.searchTokens = searchTokens ?? PostSearchTokenizer.tokens(in: combined, topics: self.topics)
        self.commentPermission = commentPermission
        self.humanBadge = humanBadge
        self.humanScore = humanScore
        self.inputDurationMs = inputDurationMs
        self.editCount = editCount
        self.deleteCount = deleteCount
        self.commentCount = commentCount
        self.purchaseCount = purchaseCount
        self.bookmarkCount = bookmarkCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.moderationStatus = moderationStatus
        self.hiddenReason = hiddenReason
        self.hiddenAt = hiddenAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, userID, title, freePreviewBody, status, price, topics, searchTokens
        case commentPermission, humanBadge, humanScore, inputDurationMs, editCount, deleteCount
        case commentCount, purchaseCount, bookmarkCount, createdAt, updatedAt, isDeleted
        case moderationStatus, hiddenReason, hiddenAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userID = try c.decode(String.self, forKey: .userID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        freePreviewBody = try c.decodeIfPresent(String.self, forKey: .freePreviewBody) ?? ""
        status = try c.decodeIfPresent(ArticleStatus.self, forKey: .status) ?? .published
        price = try c.decodeIfPresent(ArticlePrice.self, forKey: .price) ?? .free
        let combined = "\(title) \(freePreviewBody)"
        topics = try c.decodeIfPresent([String].self, forKey: .topics) ?? TopicExtractor.topics(in: combined)
        searchTokens = try c.decodeIfPresent([String].self, forKey: .searchTokens) ?? PostSearchTokenizer.tokens(in: combined, topics: topics)
        commentPermission = try c.decodeIfPresent(CommentPermission.self, forKey: .commentPermission) ?? .everyone
        humanBadge = try c.decodeIfPresent(HumanBadge.self, forKey: .humanBadge) ?? .checking
        humanScore = try c.decodeIfPresent(Int.self, forKey: .humanScore) ?? 0
        inputDurationMs = try c.decodeIfPresent(Int.self, forKey: .inputDurationMs) ?? 0
        editCount = try c.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        deleteCount = try c.decodeIfPresent(Int.self, forKey: .deleteCount) ?? 0
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        purchaseCount = try c.decodeIfPresent(Int.self, forKey: .purchaseCount) ?? 0
        bookmarkCount = try c.decodeIfPresent(Int.self, forKey: .bookmarkCount) ?? 0
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        moderationStatus = try c.decodeIfPresent(ModerationStatus.self, forKey: .moderationStatus) ?? .active
        hiddenReason = try c.decodeIfPresent(String.self, forKey: .hiddenReason)
        hiddenAt = try c.decodeIfPresent(Date.self, forKey: .hiddenAt)
    }

    var durationText: String {
        let seconds = inputDurationMs / 1000
        if seconds < 60 { return "\(seconds)秒" }
        if seconds < 3600 { return "\(seconds / 60)分" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m == 0 ? "\(h)時間" : "\(h)時間\(m)分"
    }

    var isPublished: Bool { status == .published }
    var isFree: Bool { price == .free }
}

enum TimelineItem: Identifiable {
    case post(Post)
    case article(Article)

    var id: String {
        switch self {
        case .post(let p): return "p-\(p.id)"
        case .article(let a): return "a-\(a.id)"
        }
    }

    var createdAt: Date {
        switch self {
        case .post(let p): return p.createdAt
        case .article(let a): return a.createdAt
        }
    }

    var userID: String {
        switch self {
        case .post(let p): return p.userId
        case .article(let a): return a.userID
        }
    }

    var topics: [String] {
        switch self {
        case .post(let p): return p.topics
        case .article(let a): return a.topics
        }
    }
}
