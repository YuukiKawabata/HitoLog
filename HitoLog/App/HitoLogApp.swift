import StoreKit
import SwiftUI

@main
@MainActor
struct HitoLogApp: App {
    @UIApplicationDelegateAdaptor(HitoLogAppDelegate.self) private var appDelegate
    @StateObject private var authSession = AuthSessionStore()
    @StateObject private var store = AppDataStore()
    @StateObject private var pushService = PushNotificationService.shared
    @StateObject private var analytics = AnalyticsService.shared
    @StateObject private var appReviewService = AppReviewService.shared
    @AppStorage("hasCompletedInitialExperience") private var hasCompletedInitialExperience = false

    init() {
        FirebaseBootstrap.configureIfAvailable()
        AnalyticsService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView(hasCompletedInitialExperience: $hasCompletedInitialExperience)
                .environmentObject(store)
                .environmentObject(authSession)
                .environmentObject(pushService)
                .environmentObject(analytics)
                .environmentObject(appReviewService)
                .task {
                    let isScreenshotDemoMode = isScreenshotDemoLaunch
                    if isScreenshotDemoMode {
                        hasCompletedInitialExperience = true
                        authSession.continueWithLocalPreview()
                    } else {
                        authSession.start()
                    }

                    appDelegate.installFirebaseMessagingDelegate()
                    await store.activateRemoteUser(
                        uid: isScreenshotDemoMode ? nil : authSession.currentUserID,
                        appleUserID: isScreenshotDemoMode ? nil : authSession.appleUserID,
                        displayName: authSession.displayName,
                        email: isScreenshotDemoMode ? nil : authSession.email
                    )
                    if isScreenshotDemoMode {
                        store.showScreenshotDemoData()
                    }
                    await pushService.configure(userID: isScreenshotDemoMode ? nil : authSession.currentUserID)
                    if !isScreenshotDemoMode {
                        appReviewService.recordSession()
                        analytics.identify(user: store.currentUser, email: authSession.email)
                        analytics.capture("app_ready", properties: [
                            "remote_sync_enabled": store.isRemoteSyncEnabled
                        ])
                    }
                }
                .onChange(of: authSession.currentUserID) { _, userID in
                    Task {
                        guard !isScreenshotDemoLaunch else { return }
                        await store.activateRemoteUser(
                            uid: userID,
                            appleUserID: authSession.appleUserID,
                            displayName: authSession.displayName,
                            email: authSession.email
                        )
                        await pushService.configure(userID: userID)
                        if userID == nil {
                            analytics.resetIdentity()
                        } else {
                            analytics.identify(user: store.currentUser, email: authSession.email)
                        }
                    }
                }
        }
    }

    private var isScreenshotDemoLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-HitoLogScreenshotDemo")
        #else
        false
        #endif
    }
}

private struct RootView: View {
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var appReviewService: AppReviewService
    @Binding var hasCompletedInitialExperience: Bool
    @State private var step: InitialExperienceStep = .login

    var body: some View {
        Group {
            if authSession.state == .signedOut {
                NavigationStack {
                    LoginView {
                        withAnimation(.snappy) {
                            step = .onboarding
                        }
                    }
                }
            } else if hasCompletedInitialExperience {
                MainTabView()
            } else {
                NavigationStack {
                    switch step {
                    case .login:
                        OnboardingView {
                            withAnimation(.snappy) {
                                hasCompletedInitialExperience = true
                            }
                        }
                    case .onboarding:
                        OnboardingView {
                            withAnimation(.snappy) {
                                hasCompletedInitialExperience = true
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: appReviewService.pendingRequest) { _, pendingRequest in
            guard let pendingRequest else { return }
            appReviewService.markPromptRequested(pendingRequest)
            requestReview()
        }
    }
}

private enum InitialExperienceStep {
    case login
    case onboarding
}
