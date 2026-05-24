import Foundation

struct AppUser: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var handle: String
    var bio: String
    var avatarUrl: String?
    var appleUserId: String?
    var humanLevel: Int
    var humanVerifiedPostRate: Double
    let createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    var initials: String {
        let source = displayName.isEmpty ? handle : displayName
        return String(source.prefix(1)).uppercased()
    }

    var accountAgeDays: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }
}

