import CoreGraphics
import Foundation

enum AppConstants {
    static let appName = "HitoLog"
    static var copy: String { "1日1つ、自分の言葉を残す。".localized }
    static let maxPostLength = 500
    static let maxPostMediaItems = 4
    static let maxPostVideoDurationSeconds = 60.0
    static let maxPostVideoSizeBytes: Int64 = 100 * 1024 * 1024
    static let maxPostImageDimension: CGFloat = 1_600
    static let maxMutedWordLength = 40
    static let maxFeedbackLength = 1_000
    static let minimumStarterPackFollowerCount = 1
    static let publicBaseURL = "https://hitolog-e22d2.web.app"
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
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return prompts[day % prompts.count].localized
    }
}
