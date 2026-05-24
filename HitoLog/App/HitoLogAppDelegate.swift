import UIKit
import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

final class HitoLogAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var sharedMessagingDelegate: HitoLogAppDelegate?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Self.sharedMessagingDelegate = self
        installFirebaseMessagingDelegate()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        #if canImport(FirebaseMessaging)
        guard FirebaseBootstrap.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
        #endif
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            await PushNotificationService.shared.updateFCMToken(nil)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().appDidReceiveMessage(response.notification.request.content.userInfo)
        #endif
    }

    func installFirebaseMessagingDelegate() {
        #if canImport(FirebaseMessaging)
        guard FirebaseBootstrap.isConfigured else { return }
        Messaging.messaging().delegate = self
        #endif
    }
}

#if canImport(FirebaseMessaging)
extension HitoLogAppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            await PushNotificationService.shared.updateFCMToken(fcmToken)
        }
    }
}
#endif
