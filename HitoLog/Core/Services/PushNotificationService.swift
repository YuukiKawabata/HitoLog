import Foundation
import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var fcmToken: String?
    @Published var isNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isNotificationsEnabled, forKey: Self.notificationsEnabledKey)
        }
    }

    private static let notificationsEnabledKey = "pushNotificationsEnabled"
    private let remoteStore = FirebaseDataStore()
    private var currentUserID: String?

    private override init() {
        self.isNotificationsEnabled = UserDefaults.standard.object(forKey: Self.notificationsEnabledKey) as? Bool ?? false
        super.init()
    }

    func configure(userID: String?) async {
        currentUserID = userID
        await refreshAuthorizationStatus()

        #if canImport(FirebaseMessaging)
        guard FirebaseBootstrap.isConfigured else { return }
        if let token = try? await Messaging.messaging().token() {
            await updateFCMToken(token)
        }
        #endif
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            isNotificationsEnabled = granted
            await refreshAuthorizationStatus()

            guard granted else {
                await syncNotificationPreference()
                return
            }

            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            isNotificationsEnabled = false
        }

        await syncNotificationPreference()
    }

    func setNotificationsEnabled(_ isEnabled: Bool) async {
        isNotificationsEnabled = isEnabled
        if isEnabled, authorizationStatus == .notDetermined {
            await requestAuthorization()
            return
        }

        await syncNotificationPreference()
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func updateFCMToken(_ token: String?) async {
        fcmToken = token
        await syncNotificationPreference()
    }

    private func syncNotificationPreference() async {
        guard let currentUserID, remoteStore.isAvailable else { return }

        do {
            if let fcmToken {
                try await remoteStore.saveFCMToken(
                    userID: currentUserID,
                    token: fcmToken,
                    isEnabled: isNotificationsEnabled && authorizationStatus.allowsDelivery
                )
            } else {
                try await remoteStore.updateNotificationPreference(
                    userID: currentUserID,
                    isEnabled: isNotificationsEnabled && authorizationStatus.allowsDelivery
                )
            }
        } catch {
            // Token sync is retried on the next app launch, permission toggle, or FCM refresh.
        }
    }
}

private extension UNAuthorizationStatus {
    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
