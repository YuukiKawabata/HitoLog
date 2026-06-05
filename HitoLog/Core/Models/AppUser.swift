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

struct InviteCode: Identifiable, Codable, Equatable {
    let id: String
    let code: String
    let inviterID: String
    var maxUses: Int
    var useCount: Int
    var isActive: Bool
    let createdAt: Date
    var expiresAt: Date?

    var remainingUses: Int {
        max(maxUses - useCount, 0)
    }

    var shareURL: URL {
        URL(string: "\(AppConstants.publicBaseURL)/i/\(code)")!
    }

    var shareText: String {
        "HitoLogへの招待です: \(shareURL.absoluteString)"
    }

    static func make(inviterID: String, maxUses: Int = 5) -> InviteCode {
        let code = randomCode()
        return InviteCode(
            id: code,
            code: code,
            inviterID: inviterID,
            maxUses: maxUses,
            useCount: 0,
            isActive: true,
            createdAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
    }

    static func code(from url: URL) -> String? {
        if url.scheme == "hitolog", url.host == "invite" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return normalizedCode(components?.queryItems?.first(where: { $0.name == "code" })?.value)
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2, pathComponents[0] == "i" else { return nil }
        return normalizedCode(pathComponents[1])
    }

    static func normalizedCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let allowed = value.uppercased().filter { $0.isLetter || $0.isNumber }
        guard allowed.count >= 6 && allowed.count <= 24 else { return nil }
        return String(allowed)
    }

    private static func randomCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let suffix = String((0..<8).compactMap { _ in alphabet.randomElement() })
        return "HL\(suffix)"
    }
}
