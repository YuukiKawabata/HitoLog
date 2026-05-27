import Foundation

struct Post: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let body: String
    let topics: [String]
    let searchTokens: [String]
    let mediaItems: [PostMedia]
    let shareType: PostShareType
    let sourcePostID: String?
    let sourceUserID: String?
    var commentPermission: CommentPermission
    let humanScore: Int
    let humanBadge: HumanBadge
    let inputDurationMs: Int
    let characterCount: Int
    let editCount: Int
    let deleteCount: Int
    let suspiciousBulkInputCount: Int
    let appCheckVerified: Bool
    var likeCount: Int
    var commentCount: Int
    var repostCount: Int
    var quoteCount: Int
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var moderationStatus: ModerationStatus
    var hiddenReason: String?
    var hiddenAt: Date?

    init(
        id: String,
        userId: String,
        body: String,
        topics: [String]? = nil,
        searchTokens: [String]? = nil,
        mediaItems: [PostMedia] = [],
        shareType: PostShareType = .original,
        sourcePostID: String? = nil,
        sourceUserID: String? = nil,
        commentPermission: CommentPermission = .everyone,
        humanScore: Int,
        humanBadge: HumanBadge,
        inputDurationMs: Int,
        characterCount: Int,
        editCount: Int,
        deleteCount: Int,
        suspiciousBulkInputCount: Int,
        appCheckVerified: Bool,
        likeCount: Int,
        commentCount: Int,
        repostCount: Int = 0,
        quoteCount: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        isDeleted: Bool,
        moderationStatus: ModerationStatus = .active,
        hiddenReason: String? = nil,
        hiddenAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.body = body
        self.topics = topics ?? TopicExtractor.topics(in: body)
        self.searchTokens = searchTokens ?? PostSearchTokenizer.tokens(in: body, topics: self.topics)
        self.mediaItems = mediaItems
        self.shareType = shareType
        self.sourcePostID = sourcePostID
        self.sourceUserID = sourceUserID
        self.commentPermission = commentPermission
        self.humanScore = humanScore
        self.humanBadge = humanBadge
        self.inputDurationMs = inputDurationMs
        self.characterCount = characterCount
        self.editCount = editCount
        self.deleteCount = deleteCount
        self.suspiciousBulkInputCount = suspiciousBulkInputCount
        self.appCheckVerified = appCheckVerified
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.repostCount = repostCount
        self.quoteCount = quoteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.moderationStatus = moderationStatus
        self.hiddenReason = hiddenReason
        self.hiddenAt = hiddenAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case body
        case topics
        case searchTokens
        case mediaItems
        case shareType
        case sourcePostID
        case sourceUserID
        case commentPermission
        case humanScore
        case humanBadge
        case inputDurationMs
        case characterCount
        case editCount
        case deleteCount
        case suspiciousBulkInputCount
        case appCheckVerified
        case likeCount
        case commentCount
        case repostCount
        case quoteCount
        case createdAt
        case updatedAt
        case isDeleted
        case moderationStatus
        case hiddenReason
        case hiddenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        body = try container.decode(String.self, forKey: .body)
        topics = try container.decodeIfPresent([String].self, forKey: .topics) ?? TopicExtractor.topics(in: body)
        searchTokens = try container.decodeIfPresent([String].self, forKey: .searchTokens) ?? PostSearchTokenizer.tokens(in: body, topics: topics)
        mediaItems = try container.decodeIfPresent([PostMedia].self, forKey: .mediaItems) ?? []
        shareType = try container.decodeIfPresent(PostShareType.self, forKey: .shareType) ?? .original
        sourcePostID = try container.decodeIfPresent(String.self, forKey: .sourcePostID)
        sourceUserID = try container.decodeIfPresent(String.self, forKey: .sourceUserID)
        commentPermission = try container.decodeIfPresent(CommentPermission.self, forKey: .commentPermission) ?? .everyone
        humanScore = try container.decode(Int.self, forKey: .humanScore)
        humanBadge = try container.decode(HumanBadge.self, forKey: .humanBadge)
        inputDurationMs = try container.decode(Int.self, forKey: .inputDurationMs)
        characterCount = try container.decode(Int.self, forKey: .characterCount)
        editCount = try container.decode(Int.self, forKey: .editCount)
        deleteCount = try container.decode(Int.self, forKey: .deleteCount)
        suspiciousBulkInputCount = try container.decode(Int.self, forKey: .suspiciousBulkInputCount)
        appCheckVerified = try container.decode(Bool.self, forKey: .appCheckVerified)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        repostCount = try container.decodeIfPresent(Int.self, forKey: .repostCount) ?? 0
        quoteCount = try container.decodeIfPresent(Int.self, forKey: .quoteCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isDeleted = try container.decode(Bool.self, forKey: .isDeleted)
        moderationStatus = try container.decodeIfPresent(ModerationStatus.self, forKey: .moderationStatus) ?? .active
        hiddenReason = try container.decodeIfPresent(String.self, forKey: .hiddenReason)
        hiddenAt = try container.decodeIfPresent(Date.self, forKey: .hiddenAt)
    }
}

enum PostShareType: String, Codable, Equatable {
    case original
    case repost
    case quote
}

enum CommentPermission: String, Codable, CaseIterable, Identifiable, Equatable {
    case everyone
    case following
    case closed

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .everyone:
            return "全員"
        case .following:
            return "フォロー中のみ"
        case .closed:
            return "不可"
        }
    }

    var detailText: String {
        switch self {
        case .everyone:
            return "すべてのユーザーがコメントできます。"
        case .following:
            return "あなたがフォローしているユーザーだけコメントできます。"
        case .closed:
            return "この投稿にはコメントできません。"
        }
    }

    var systemImage: String {
        switch self {
        case .everyone:
            return "bubble.right"
        case .following:
            return "person.2"
        case .closed:
            return "bubble.right.slash"
        }
    }
}

enum ModerationStatus: String, Codable, Equatable {
    case active
    case reviewRequired
    case hidden
}

struct TopicTrend: Identifiable, Equatable {
    let topic: String
    let postCount: Int

    var id: String { topic }
    var displayText: String { "#\(topic)" }
}

struct MutedWord: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    let word: String
    let normalizedWord: String
    let createdAt: Date

    static func makeID(userID: String, normalizedWord: String) -> String {
        "\(userID)_\(stableIDComponent(for: normalizedWord))"
    }

    private static func stableIDComponent(for value: String) -> String {
        dataBytes(for: value)
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(64)
            .description
    }

    private static func dataBytes(for value: String) -> [UInt8] {
        Array(value.data(using: .utf8) ?? Data())
    }
}

enum MutedWordNormalizer {
    static func normalize(_ value: String) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value
        return folded
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedPostText(_ post: Post) -> String {
        normalize(([post.body] + post.topics.map { "#\($0)" }).joined(separator: " "))
    }

    static func containsMutedWord(in post: Post, mutedWords: [MutedWord]) -> Bool {
        containsMutedWord(inNormalizedText: normalizedPostText(post), mutedWords: mutedWords)
    }

    static func containsMutedWord(in comment: Comment, mutedWords: [MutedWord]) -> Bool {
        containsMutedWord(inNormalizedText: normalize(comment.body), mutedWords: mutedWords)
    }

    private static func containsMutedWord(inNormalizedText text: String, mutedWords: [MutedWord]) -> Bool {
        guard !text.isEmpty, !mutedWords.isEmpty else { return false }
        return mutedWords.contains { word in
            !word.normalizedWord.isEmpty && text.contains(word.normalizedWord)
        }
    }
}

enum TopicExtractor {
    static let maxTopicsPerPost = 8
    static let maxTopicLength = 32

    static func topics(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawToken in text.split(whereSeparator: { $0.isWhitespace }) {
            guard let topic = normalizedTopic(from: rawToken), !seen.contains(topic) else {
                continue
            }

            seen.insert(topic)
            result.append(topic)
            if result.count >= maxTopicsPerPost {
                break
            }
        }

        return result
    }

    static func normalizedTopicQuery(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.first == "#" || trimmed.first == "＃" {
            return normalizedTopic(from: Substring(trimmed))
        }
        return normalizedTopicBody(trimmed)
    }

    private static func normalizedTopic(from token: Substring) -> String? {
        guard token.first == "#" || token.first == "＃" else { return nil }
        let body = token.dropFirst()
        return normalizedTopicBody(String(body))
    }

    private static func normalizedTopicBody(_ raw: String) -> String? {
        let allowedScalars = raw.unicodeScalars.prefix { scalar in
            CharacterSet.alphanumerics.contains(scalar)
            || scalar == "_"
            || scalar == "ー"
            || scalar == "-"
        }
        let normalized = String(String.UnicodeScalarView(allowedScalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-ー"))
            .lowercased()

        guard normalized.count >= 2 else { return nil }
        return String(normalized.prefix(maxTopicLength))
    }
}

enum PostSearchTokenizer {
    static let maxTokens = 80
    static let maxTokenLength = 32

    static func tokens(in text: String, topics: [String] = []) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        func append(_ rawValue: String) {
            let token = normalized(rawValue)
            guard token.count >= 2, !seen.contains(token) else { return }
            seen.insert(token)
            result.append(token)
        }

        topics.forEach(append)

        let words = text.lowercased().split { character in
            !(character.isLetter || character.isNumber || character == "_" || character == "-" || character == "ー")
        }
        words.forEach { append(String($0)) }

        let compact = normalized(text)
        let characters = Array(compact)
        if characters.count >= 2 {
            for size in 2...min(4, characters.count) {
                guard result.count < maxTokens else { break }
                for index in 0...(characters.count - size) {
                    append(String(characters[index..<(index + size)]))
                    if result.count >= maxTokens { break }
                }
            }
        }

        return Array(result.prefix(maxTokens))
    }

    static func primaryToken(for query: String) -> String? {
        let queryToken = normalized(query)
        let candidates = tokens(in: query)
        if candidates.contains(queryToken) {
            return queryToken
        }
        return candidates.first
    }

    static func matches(_ post: Post, query: String) -> Bool {
        let needle = normalized(query)
        guard !needle.isEmpty else { return false }
        return normalized(post.body).contains(needle)
            || post.topics.contains(where: { normalized($0).contains(needle) })
    }

    private static func normalized(_ rawValue: String) -> String {
        let allowedScalars = rawValue.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_"
                || scalar == "-"
                || scalar == "ー"
        }
        let value = String(String.UnicodeScalarView(allowedScalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-ー"))
        return String(value.prefix(maxTokenLength))
    }
}

enum PostMediaType: String, Codable, Equatable {
    case image
    case video
}

struct PostMedia: Identifiable, Codable, Equatable {
    let id: String
    let type: PostMediaType
    let storagePath: String
    let downloadURL: String
    let thumbnailURL: String?
    let width: Int
    let height: Int
    let durationMs: Int?
    let sizeBytes: Int64
    let sortOrder: Int
}
