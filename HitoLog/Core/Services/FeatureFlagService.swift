import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

@MainActor
final class FeatureFlagService: ObservableObject {
    static let shared = FeatureFlagService()

    // 既定値は公開中の Remote Config（remoteconfig.template.json）に合わせる。
    // 初回起動やオフラインで取得できないときも、2.0 の輪の画面を出し、閲覧のみの旧SNSに書き込ませない。
    @Published private(set) var enableCircles = true
    @Published private(set) var circlesAsDefaultHome = true
    @Published private(set) var showLegacyPublicTimeline = false
    @Published private(set) var enableCircleImages = true
    @Published private(set) var enableCircleComments = true
    @Published private(set) var enableCircleReactions = true
    @Published private(set) var enableCirclePush = true
    @Published private(set) var enableCircleMoments = false
    /// 旧SNS（みんなの投稿）の作成・編集。サーバーのルール（legacySocialWritesEnabled）と合わせて切り替える。
    @Published private(set) var legacySocialWritesEnabled = false

    private init() {}

    func refresh(for userID: String?) async {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseBootstrap.isConfigured else { return }
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 900
        config.configSettings = settings
        config.setDefaults([
            "enable_circles": true as NSNumber,
            "circles_as_default_home": true as NSNumber,
            "show_legacy_public_timeline": false as NSNumber,
            "enable_circle_images": true as NSNumber,
            "enable_circle_comments": true as NSNumber,
            "enable_circle_reactions": true as NSNumber,
            "enable_circle_push": true as NSNumber,
            "enable_circle_moments": false as NSNumber,
            "legacy_social_writes_enabled": false as NSNumber,
            "circles_internal_user_ids": "" as NSString
        ])
        do {
            _ = try await config.fetchAndActivate()
            let globallyEnabled = config["enable_circles"].boolValue
            let allowlist = Set(config["circles_internal_user_ids"].stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            enableCircles = globallyEnabled || userID.map(allowlist.contains) == true
            circlesAsDefaultHome = enableCircles && config["circles_as_default_home"].boolValue
            showLegacyPublicTimeline = config["show_legacy_public_timeline"].boolValue
            enableCircleImages = enableCircles && config["enable_circle_images"].boolValue
            enableCircleComments = enableCircles && config["enable_circle_comments"].boolValue
            enableCircleReactions = enableCircles && config["enable_circle_reactions"].boolValue
            enableCirclePush = enableCircles && config["enable_circle_push"].boolValue
            enableCircleMoments = enableCircles && config["enable_circle_moments"].boolValue
            legacySocialWritesEnabled = config["legacy_social_writes_enabled"].boolValue
        } catch {
            // Keep the conservative in-memory defaults or the last activated values.
        }
        #endif
    }
}
