import Foundation

struct CircleInviteRouter {
    func route(for url: URL) -> CircleRoute? {
        if ["wamori", "hitolog"].contains(url.scheme?.lowercased() ?? "") {
            if url.host == "circle" || url.host == "invite" {
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                if let token = normalizedToken(query?.first(where: { $0.name == "token" })?.value) {
                    return .invite(token: token)
                }
                if let id = query?.first(where: { $0.name == "id" })?.value,
                   isValidIdentifier(id) {
                    return .circle(id: id)
                }
            }
        }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        if components[0] == "c", let token = normalizedToken(components[1]) {
            return .invite(token: token)
        }
        if components[0] == "circle", isValidIdentifier(components[1]) {
            return .circle(id: components[1])
        }
        return nil
    }

    private func normalizedToken(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (32...512).contains(trimmed.count),
              trimmed.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && !value.contains("/")
    }
}
