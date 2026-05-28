import Foundation

struct AppFeedback: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    let category: AppFeedbackCategory
    let message: String
    let contactEmail: String?
    let appVersion: String
    let buildNumber: String
    let platform: String
    let createdAt: Date
    var status: String = "new"
}

enum AppFeedbackCategory: String, Codable, CaseIterable, Identifiable, Equatable {
    case bug
    case usability
    case featureRequest
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug:
            return "不具合"
        case .usability:
            return "使いづらさ"
        case .featureRequest:
            return "要望"
        case .other:
            return "その他"
        }
    }

    var systemImage: String {
        switch self {
        case .bug:
            return "ladybug"
        case .usability:
            return "hand.tap"
        case .featureRequest:
            return "sparkles"
        case .other:
            return "bubble.left.and.bubble.right"
        }
    }
}
