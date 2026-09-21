import Foundation

#if canImport(FirebaseRemoteConfig)
import FirebaseRemoteConfig
#endif

@MainActor
final class FeatureFlagService: ObservableObject {
    static let shared = FeatureFlagService()

    @Published private(set) var enableCircles = false
    @Published private(set) var circlesAsDefaultHome = false
    @Published private(set) var showLegacyPublicTimeline = true
    @Published private(set) var enableCircleImages = false
    @Published private(set) var enableCircleComments = false
    @Published private(set) var enableCircleReactions = false
    @Published private(set) var enableCirclePush = false
    @Published private(set) var enableCircleMoments = false

    private init() {}

    func refresh(for userID: String?) async {
        #if canImport(FirebaseRemoteConfig)
        guard FirebaseBootstrap.isConfigured else { return }
        let config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 900
        config.configSettings = settings
        config.setDefaults([
            "enable_circles": false as NSNumber,
            "circles_as_default_home": false as NSNumber,
            "show_legacy_public_timeline": true as NSNumber,
            "enable_circle_images": false as NSNumber,
            "enable_circle_comments": false as NSNumber,
            "enable_circle_reactions": false as NSNumber,
            "enable_circle_push": false as NSNumber,
            "enable_circle_moments": false as NSNumber,
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
        } catch {
            // Keep the conservative in-memory defaults or the last activated values.
        }
        #endif
    }
}
