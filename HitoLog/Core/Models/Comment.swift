import Foundation

struct Comment: Identifiable, Codable, Equatable {
    let id: String
    let postId: String
    let userId: String
    let body: String
    let humanScore: Int
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var moderationStatus: ModerationStatus = .active
    var hiddenReason: String? = nil
    var hiddenAt: Date? = nil
}

enum AppNotificationType: String, Codable, Equatable {
    case comment
    case like
    case follow
    case repost
    case quote
    case mention
}

struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let type: AppNotificationType
    let recipientID: String
    let actorID: String
    let postID: String?
    let text: String
    let createdAt: Date
    var isRead: Bool
    var readAt: Date?
}
