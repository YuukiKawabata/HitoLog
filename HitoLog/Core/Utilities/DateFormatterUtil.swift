import Foundation

enum DateFormatterUtil {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relativeString(from date: Date, relativeTo referenceDate: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

