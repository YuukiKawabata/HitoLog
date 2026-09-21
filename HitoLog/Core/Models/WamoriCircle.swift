import Foundation

enum CircleStatus: String, Codable, CaseIterable {
    case active
    case deleting
    case deleted
}

enum CircleMemberRole: String, Codable {
    case owner
    case member
}

enum CircleMemberStatus: String, Codable {
    case active
    case leaving
    case removed
}

struct WamoriCircle: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var emoji: String
    var ownerID: String
    var memberCount: Int
    let maxMembers: Int
    var status: CircleStatus
    let createdAt: Date
    var updatedAt: Date

    var displayTitle: String {
        emoji.isEmpty ? name : "\(emoji) \(name)"
    }
}

struct CircleMember: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    var role: CircleMemberRole
    let joinedAt: Date
    var status: CircleMemberStatus
}

enum CircleMediaType: String, Codable {
    case image
    case momentVideo
}

struct CircleMedia: Identifiable, Codable, Equatable {
    let id: String
    let type: CircleMediaType
    let storagePath: String
    let width: Int
    let height: Int
    let durationMs: Int?
    let sizeBytes: Int64
}

struct CircleEntry: Identifiable, Codable, Equatable {
    let id: String
    let circleID: String
    let authorID: String
    let dateKey: String
    var body: String
    var mediaItems: [CircleMedia]
    let promptID: String
    let promptTextSnapshot: String
    var humanScore: Int
    var humanBadge: HumanBadge
    var aiAssisted: Bool
    var inputDurationMs: Int
    var characterCount: Int
    var editCount: Int
    var deleteCount: Int
    var suspiciousBulkInputCount: Int
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var moderationStatus: ModerationStatus
    var commentCount: Int
    var reactionCounts: [String: Int]
}

struct CircleComment: Identifiable, Codable, Equatable {
    let id: String
    let circleID: String
    let entryID: String
    let userID: String
    let body: String
    let createdAt: Date
    var isDeleted: Bool
    var moderationStatus: ModerationStatus
}

struct CircleReaction: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    var kind: ReactionKind
    let createdAt: Date
    var updatedAt: Date
}

enum CircleInviteState: String, Codable {
    case active
    case invalid
    case expired
    case used
    case full
}

struct CircleInvitePreview: Codable, Equatable {
    let circleDisplayName: String
    let circleEmoji: String
    let ownerDisplayName: String
    let memberCount: Int
    let maxMembers: Int
    let expiresAt: Date
    let state: CircleInviteState
}

struct CircleInviteSummary: Identifiable, Codable, Equatable {
    let id: String
    let expiresAt: Date
    let status: CircleInviteState
}

struct CreatedCircleInvite: Equatable {
    let id: String
    let token: String
    let expiresAt: Date

    var shareURL: URL? {
        URL(string: "\(AppConstants.publicBaseURL)/c/\(token)")
    }
}

enum CircleRoute: Equatable {
    case invite(token: String)
    case circle(id: String)
}

enum CircleServiceError: LocalizedError, Equatable {
    case unavailable
    case invalidResponse
    case invalidInvite
    case inviteExpired
    case inviteUsed
    case circleFull
    case alreadyMember
    case entryAlreadyExists
    case editWindowClosed
    case permissionDenied
    case ownershipTransferRequired
    case validation(String)
    case operationInProgress
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "輪の機能を利用できません。"
        case .invalidResponse: return "サーバーから正しい応答を受け取れませんでした。"
        case .invalidInvite: return "この招待リンクは利用できません。"
        case .inviteExpired: return "この招待リンクの期限が切れています。"
        case .inviteUsed: return "この招待リンクはすでに使用されています。"
        case .circleFull: return "この輪は定員に達しています。"
        case .alreadyMember: return "すでにこの輪へ参加しています。"
        case .entryAlreadyExists: return "今日の記録はすでにあります。"
        case .editWindowClosed: return "過去の記録は編集できません。"
        case .permissionDenied: return "この操作を行う権限がありません。"
        case .ownershipTransferRequired: return "アカウントを削除する前に、参加者がいる輪のオーナーを移譲してください。"
        case .validation(let message), .server(let message): return message
        case .operationInProgress: return "処理中です。しばらくお待ちください。"
        case .network: return "通信できませんでした。内容を保持して再試行できます。"
        }
    }
}

enum CircleEntryDraftValidator {
    static let maximumBodyCharacters = 500

    static func isValid(body: String, hasMedia: Bool) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.count <= maximumBodyCharacters && (!trimmed.isEmpty || hasMedia)
    }
}
