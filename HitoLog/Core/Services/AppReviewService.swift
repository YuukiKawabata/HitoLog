import Combine
import StoreKit
import UIKit

@MainActor
final class AppReviewService: ObservableObject {
    static let shared = AppReviewService()

    struct PendingRequest: Identifiable, Equatable {
        let id = UUID()
        let reason: ReviewMoment
    }

    enum ReviewMoment: String {
        case postCreated
        case commentCreated
        case postLiked
        case postBookmarked
        case userFollowed

        var score: Int {
            switch self {
            case .postCreated:
                return 2
            case .commentCreated, .postLiked, .postBookmarked, .userFollowed:
                return 1
            }
        }
    }

    @Published private(set) var pendingRequest: PendingRequest?

    private enum Keys {
        static let firstLaunchDate = "appReviewFirstLaunchDate"
        static let lastSessionDate = "appReviewLastSessionDate"
        static let sessionCount = "appReviewSessionCount"
        static let positiveMomentScore = "appReviewPositiveMomentScore"
        static let lastPromptDate = "appReviewLastPromptDate"
        static let lastPromptVersion = "appReviewLastPromptVersion"
    }

    private let defaults: UserDefaults
    private var scheduledPromptTask: Task<Void, Never>?

    private let minimumSessionCount = 3
    private let minimumPositiveMomentScore = 4
    private let minimumDaysSinceFirstLaunch: TimeInterval = 2 * 24 * 60 * 60
    private let minimumDaysBetweenPrompts: TimeInterval = 60 * 24 * 60 * 60
    private let minimumSecondsBetweenSessions: TimeInterval = 30 * 60
    private let promptDelayNanoseconds: UInt64 = 2_000_000_000

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordSession() {
        guard !isScreenshotDemoLaunch else { return }

        let now = Date()
        if defaults.object(forKey: Keys.firstLaunchDate) == nil {
            defaults.set(now, forKey: Keys.firstLaunchDate)
        }

        if let lastSessionDate = defaults.object(forKey: Keys.lastSessionDate) as? Date,
           now.timeIntervalSince(lastSessionDate) < minimumSecondsBetweenSessions {
            return
        }

        defaults.set(now, forKey: Keys.lastSessionDate)
        defaults.set(defaults.integer(forKey: Keys.sessionCount) + 1, forKey: Keys.sessionCount)
    }

    func recordPositiveMoment(_ moment: ReviewMoment) {
        guard !isScreenshotDemoLaunch else { return }

        let nextScore = defaults.integer(forKey: Keys.positiveMomentScore) + moment.score
        defaults.set(nextScore, forKey: Keys.positiveMomentScore)
        schedulePromptIfEligible(reason: moment)
    }

    func markPromptRequested(_ request: PendingRequest) {
        guard pendingRequest == request else { return }

        pendingRequest = nil
        defaults.set(Date(), forKey: Keys.lastPromptDate)
        defaults.set(currentAppVersion, forKey: Keys.lastPromptVersion)
        defaults.set(0, forKey: Keys.positiveMomentScore)
        AnalyticsService.shared.capture("app_review_prompt_requested", properties: [
            "reason": request.reason.rawValue,
            "session_count": defaults.integer(forKey: Keys.sessionCount)
        ])
    }

    static func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        SKStoreReviewController.requestReview(in: scene)
    }

    private func schedulePromptIfEligible(reason: ReviewMoment) {
        guard pendingRequest == nil,
              scheduledPromptTask == nil,
              isEligibleForPrompt() else {
            return
        }

        let delay = promptDelayNanoseconds
        scheduledPromptTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            self?.publishPromptIfStillEligible(reason: reason)
        }
    }

    private func publishPromptIfStillEligible(reason: ReviewMoment) {
        scheduledPromptTask = nil
        guard pendingRequest == nil, isEligibleForPrompt() else { return }
        pendingRequest = PendingRequest(reason: reason)
    }

    private func isEligibleForPrompt(now: Date = Date()) -> Bool {
        guard defaults.integer(forKey: Keys.sessionCount) >= minimumSessionCount,
              defaults.integer(forKey: Keys.positiveMomentScore) >= minimumPositiveMomentScore,
              defaults.string(forKey: Keys.lastPromptVersion) != currentAppVersion,
              let firstLaunchDate = defaults.object(forKey: Keys.firstLaunchDate) as? Date,
              now.timeIntervalSince(firstLaunchDate) >= minimumDaysSinceFirstLaunch else {
            return false
        }

        if let lastPromptDate = defaults.object(forKey: Keys.lastPromptDate) as? Date,
           now.timeIntervalSince(lastPromptDate) < minimumDaysBetweenPrompts {
            return false
        }

        return true
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var isScreenshotDemoLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-HitoLogScreenshotDemo")
        #else
        false
        #endif
    }
}
