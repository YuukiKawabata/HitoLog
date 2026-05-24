import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum FirebaseBootstrap {
    private(set) static var isConfigured = false

    @discardableResult
    static func configureIfAvailable() -> Bool {
        #if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else {
            isConfigured = true
            return true
        }

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            isConfigured = false
            return false
        }

        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(HitoLogAppCheckProviderFactory())
        #endif
        #endif

        FirebaseApp.configure()
        isConfigured = true
        return true
        #else
        isConfigured = false
        return false
        #endif
    }
}

#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
private final class HitoLogAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
    }
}
#endif
