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
}

