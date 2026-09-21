import Foundation

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
    case circle
    case circleEntry
    case circleComment
    case circleMember
    case other

    var displayText: String {
        switch self {
        case .post: return "投稿".localized
        case .comment: return "コメント".localized
        case .user: return "ユーザー".localized
        case .article: return "記事".localized
        case .circle: return "輪"
        case .circleEntry: return "輪の記録"
        case .circleComment: return "輪のコメント"
        case .circleMember: return "輪のメンバー"
        case .other: return "その他".localized
        }
    }
}
