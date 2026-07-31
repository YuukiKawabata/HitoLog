import Foundation

enum L10n {
    static var prefersEnglish: Bool {
        Locale.preferredLanguages.first?.hasPrefix("en") == true
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: NSLocalizedString(key, comment: ""),
            locale: Locale.current,
            arguments: arguments
        )
    }
}

extension String {
    var localized: String {
        L10n.text(self)
    }
}
