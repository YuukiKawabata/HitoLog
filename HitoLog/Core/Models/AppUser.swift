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
    var isAdmin: Bool = false
    var isSuspended: Bool = false
    var followerCount: Int = 0
    var followingCount: Int = 0
    var website: String? = nil
    var location: String? = nil
    var occupation: String? = nil

    /// 表示用にスキーム補完したウェブサイトURL
    var websiteURL: URL? {
        guard let website, !website.isEmpty else { return nil }
        if website.lowercased().hasPrefix("http://") || website.lowercased().hasPrefix("https://") {
            return URL(string: website)
        }
        return URL(string: "https://\(website)")
    }

    /// 表示用にスキームを省いたウェブサイト文字列
    var websiteDisplayText: String? {
        guard let website, !website.isEmpty else { return nil }
        return website
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var initials: String {
        let source = displayName.isEmpty ? handle : displayName
        return String(source.prefix(1)).uppercased()
    }

    var displayNameLowercase: String {
        displayName.lowercased()
    }

    var handleLowercase: String {
        handle.lowercased()
    }

    var accountAgeDays: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }
}
