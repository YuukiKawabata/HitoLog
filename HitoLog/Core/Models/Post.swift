import Foundation

struct Post: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let body: String
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
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
}

