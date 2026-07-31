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

struct FutureReflection: Identifiable, Codable, Equatable {
    let id: String
    let postID: String
    let body: String
    let createdAt: Date
    let deliveryDate: Date
}

@MainActor
final class FutureReflectionService: ObservableObject {
    static let shared = FutureReflectionService()

    @Published private(set) var reflections: [FutureReflection]

    private static let storageKeyPrefix = "futureReflections"
    private static let notificationPrefix = "future-reflection-"
    private let notificationCenter = UNUserNotificationCenter.current()
    private var activeUserID = "local"

    private init() {
        reflections = []
        load()
    }

    var deliveredReflections: [FutureReflection] {
        reflections
            .filter { $0.deliveryDate <= Date() }
            .sorted { $0.deliveryDate > $1.deliveryDate }
    }

    var upcomingReflections: [FutureReflection] {
        reflections
            .filter { $0.deliveryDate > Date() }
            .sorted { $0.deliveryDate < $1.deliveryDate }
    }

    func activate(userID: String?) {
        let normalizedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        activeUserID = normalizedUserID.isEmpty ? "local" : normalizedUserID
        load()
    }

    @discardableResult
    func schedule(post: Post, calendar: Calendar = .current) async -> FutureReflection {
        let deliveryDate = calendar.date(byAdding: .month, value: 1, to: post.createdAt)
            ?? post.createdAt.addingTimeInterval(30 * 24 * 60 * 60)
        let reflection = FutureReflection(
            id: UUID().uuidString,
            postID: post.id,
            body: post.body,
            createdAt: post.createdAt,
            deliveryDate: deliveryDate
        )

        reflections.append(reflection)
        reflections.sort { $0.deliveryDate < $1.deliveryDate }
        persist()

        let settings = await notificationCenter.notificationSettings()
        let isAuthorized: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .notDetermined:
            isAuthorized = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }

        if isAuthorized {
            let content = UNMutableNotificationContent()
            content.title = "1か月前の自分から".localized
            content.body = String(post.body.prefix(90))
            content.sound = .default
            content.userInfo = [
                "hitolog_kind": "future_reflection",
                "post_id": post.id
            ]

            let interval = max(deliveryDate.timeIntervalSinceNow, 1)
            let request = UNNotificationRequest(
                identifier: Self.notificationPrefix + reflection.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await notificationCenter.add(request)
        }

        return reflection
    }

    func remove(_ reflection: FutureReflection) {
        reflections.removeAll { $0.id == reflection.id }
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationPrefix + reflection.id]
        )
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(reflections) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([FutureReflection].self, from: data) else {
            reflections = []
            return
        }
        reflections = stored.sorted { $0.deliveryDate < $1.deliveryDate }
    }

    private var storageKey: String {
        Self.storageKeyPrefix + "." + activeUserID
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
