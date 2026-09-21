import CoreGraphics
import Foundation

enum AppConstants {
    static let appName = "Wamori"
    static var copy: String { "大切な人と、今日をひとつずつ。".localized }
    static let maxPostLength = 500
    static let maxPostMediaItems = 4
    static let maxPostVideoDurationSeconds = 60.0
    static let maxPostVideoSizeBytes: Int64 = 100 * 1024 * 1024
    static let maxPostImageDimension: CGFloat = 1_600
    static let maxMutedWordLength = 40
    static let maxFeedbackLength = 1_000
    static let minimumStarterPackFollowerCount = 1
    static let canonicalPublicBaseURL = "https://wamori.app"
    // Use the live Firebase host until the custom domain has been acquired and connected.
    // Both hosts remain accepted by CircleInviteRouter, so switching later is backward-compatible.
    static let publicBaseURL = "https://hitolog-e22d2.web.app"
    static let legacyPublicBaseURL = "https://hitolog-e22d2.web.app"
    static let maxCircleMembers = 5
    static let maxOwnedCircles = 5
    static let maxJoinedCircles = 20
    static let maxCircleImageBytes: Int64 = 10 * 1024 * 1024
}

enum DailyPrompt {
    private static let prompts = [
        "今日、心に残ったことは？",
        "いま、誰かに伝えたいことは？",
        "今日の自分を一言で残すなら？",
        "小さくても、うれしかったことは？",
        "今日、考えが変わったことは？",
        "いま手放したい気持ちは？",
        "明日の自分に残したい言葉は？"
    ]

    static var current: String {
        text(for: CircleDataStore.dateKey(for: Date(), timeZone: .current))
    }

    static func text(for dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateKey) else { return prompts[0].localized }
        let day = Int(floor(date.timeIntervalSince1970 / 86_400))
        return prompts[abs(day) % prompts.count].localized
    }
}
