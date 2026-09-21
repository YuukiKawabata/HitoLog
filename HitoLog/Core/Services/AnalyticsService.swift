import Foundation

#if canImport(PostHog)
import PostHog
#endif

@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    @Published private(set) var isConfigured = false
    @Published private(set) var isEnabled: Bool

    private let enabledKey = "analyticsCollectionEnabled"
    private let defaultHost = "https://us.i.posthog.com"

    private init() {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: enabledKey)
        }
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
    }

    func configure() {
        guard !isConfigured else { return }
        guard let projectToken = infoString(for: "PostHogProjectToken"),
              !isPlaceholder(projectToken) else {
            return
        }

        let host = infoString(for: "PostHogHost").flatMap { isPlaceholder($0) ? nil : $0 } ?? defaultHost

        #if canImport(PostHog)
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.sessionReplay = false
        config.errorTrackingConfig.autoCapture = isEnabled
        config.optOut = !isEnabled
        #if DEBUG
        config.debug = true
        #endif
        PostHogSDK.shared.setup(config)
        isConfigured = true
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)

        #if canImport(PostHog)
        guard isConfigured else { return }
        if enabled {
            PostHogSDK.shared.optIn()
            capture("analytics_enabled")
        } else {
            PostHogSDK.shared.optOut()
        }
        #endif
    }

    func identify(user: AppUser, email: String? = nil) {
        guard isConfigured, isEnabled else { return }

        #if canImport(PostHog)
        // PostHogの匿名distinct IDを維持し、Firebase UIDやメールアドレスは送らない。
        PostHogSDK.shared.capture("account_context", properties: enriched([
            "human_level": user.humanLevel,
            "human_verified_post_rate": user.humanVerifiedPostRate,
            "account_age_days": user.accountAgeDays,
            "is_admin": user.isAdmin,
            "signup_email_provided": email?.isEmpty == false
        ]))
        #endif
    }

    func resetIdentity() {
        guard isConfigured else { return }

        #if canImport(PostHog)
        PostHogSDK.shared.reset()
        #endif
    }

    func screen(_ name: String, properties: [String: Any] = [:]) {
        guard isConfigured, isEnabled else { return }

        #if canImport(PostHog)
        PostHogSDK.shared.screen(name, properties: enriched(properties))
        #endif
    }

    func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isConfigured, isEnabled else { return }

        #if canImport(PostHog)
        PostHogSDK.shared.capture(event, properties: enriched(properties))
        #endif
    }

    private func enriched(_ properties: [String: Any]) -> [String: Any] {
        var next = privacySafeProperties(properties)
        next["app_version"] = appVersion
        next["build_number"] = buildNumber
        next["platform"] = "ios"
        return next
    }

    /// Circleの内容や識別子が、将来イベントを追加した際にも誤って送信されないための最終防波堤。
    func privacySafeProperties(_ properties: [String: Any]) -> [String: Any] {
        let forbiddenFragments = [
            "userid", "authorid", "actorid", "ownerid", "recipientid", "memberid",
            "circleid", "circlename", "targetid", "postid", "commentid", "entryid",
            "inviteid", "requestid", "transactionid", "body", "commenttext", "token", "storagepath"
        ]
        return properties.filter { element in
            let normalizedKey = element.key.lowercased().filter { $0.isLetter || $0.isNumber }
            return !forbiddenFragments.contains { normalizedKey.contains($0) }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    private func infoString(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func isPlaceholder(_ value: String) -> Bool {
        value.hasPrefix("$(") || value.contains("<") || value.contains(">")
    }
}
