import StoreKit
import SwiftUI

@main
@MainActor
struct HitoLogApp: App {
    @UIApplicationDelegateAdaptor(HitoLogAppDelegate.self) private var appDelegate
    @StateObject private var authSession = AuthSessionStore()
    @StateObject private var store = AppDataStore()
    @StateObject private var circleStore = CircleDataStore()
    @StateObject private var featureFlags = FeatureFlagService.shared
    @StateObject private var pushService = PushNotificationService.shared
    @StateObject private var futureReflectionService = FutureReflectionService.shared
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
                .environmentObject(circleStore)
                .environmentObject(featureFlags)
                .environmentObject(authSession)
                .environmentObject(pushService)
                .environmentObject(futureReflectionService)
                .environmentObject(analytics)
                .environmentObject(appReviewService)
                .task {
                    #if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("-WamoriScreenshotMode") else { return }
                    #endif
                    authSession.start()
                    appDelegate.installFirebaseMessagingDelegate()
                    await store.activateRemoteUser(
                        uid: authSession.currentUserID,
                        appleUserID: authSession.appleUserID,
                        displayName: authSession.displayName,
                        email: authSession.email
                    )
                    await circleStore.activate(userID: authSession.currentUserID, timeZoneIdentifier: store.currentUser.timeZoneIdentifier)
                    await featureFlags.refresh(for: authSession.currentUserID)
                    futureReflectionService.activate(userID: store.currentUser.id)
                    await pushService.configure(userID: authSession.currentUserID)
                    appReviewService.recordSession()
                    if authSession.currentUserID != nil {
                        analytics.identify(user: store.currentUser, email: authSession.email)
                    } else {
                        analytics.resetIdentity()
                    }
                    analytics.capture("app_ready", properties: [
                        "remote_sync_enabled": store.isRemoteSyncEnabled
                    ])
                }
                .onChange(of: authSession.currentUserID) { _, userID in
                    Task {
                        await store.activateRemoteUser(
                            uid: userID,
                            appleUserID: authSession.appleUserID,
                            displayName: authSession.displayName,
                            email: authSession.email
                        )
                        await circleStore.activate(userID: userID, timeZoneIdentifier: store.currentUser.timeZoneIdentifier)
                        await featureFlags.refresh(for: userID)
                        futureReflectionService.activate(userID: store.currentUser.id)
                        await pushService.configure(userID: userID)
                        if userID == nil {
                            analytics.resetIdentity()
                        } else {
                            analytics.identify(user: store.currentUser, email: authSession.email)
                        }
                    }
                }
                .onOpenURL { url in
                    if !circleStore.handleIncomingURL(url) {
                        store.handleIncomingURL(url)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    if !circleStore.handleIncomingURL(url) {
                        store.handleIncomingURL(url)
                    }
                }
        }
    }

}

private struct RootView: View {
    @Environment(\.requestReview) private var requestReview
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var appReviewService: AppReviewService
    @Binding var hasCompletedInitialExperience: Bool
    @AppStorage("hasSeenWamoriMigrationV2") private var hasSeenWamoriMigration = false
    @State private var step: InitialExperienceStep = .login

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-WamoriScreenshotMode") {
                WamoriScreenshotRootView()
            } else {
                authenticatedContent
            }
            #else
            authenticatedContent
            #endif
        }
        .onChange(of: appReviewService.pendingRequest) { _, pendingRequest in
            guard let pendingRequest else { return }
            appReviewService.markPromptRequested(pendingRequest)
            requestReview()
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if authSession.state == .signedOut {
                NavigationStack {
                    LoginView {
                        withAnimation(.snappy) {
                            step = .onboarding
                        }
                    }
                }
            } else if hasCompletedInitialExperience && !hasSeenWamoriMigration {
                WamoriMigrationView {
                    hasSeenWamoriMigration = true
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
                                hasSeenWamoriMigration = true
                            }
                        }
                    case .onboarding:
                        OnboardingView {
                            withAnimation(.snappy) {
                                hasCompletedInitialExperience = true
                                hasSeenWamoriMigration = true
                            }
                        }
                    }
                }
        }
    }
}

#if DEBUG
private struct WamoriScreenshotRootView: View {
    @EnvironmentObject private var circles: CircleDataStore

    private var screen: String {
        guard let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-WamoriScreenshotScreen"),
              ProcessInfo.processInfo.arguments.indices.contains(index + 1) else { return "home" }
        return ProcessInfo.processInfo.arguments[index + 1]
    }

    var body: some View {
        Group {
            if let circle = circles.circles.first {
                switch screen {
                case "compose": NavigationStack { ComposeCircleEntryView(circle: circle, editing: nil) }
                case "self": NavigationStack { WamoriSelfView() }
                default: NavigationStack { CircleHomeView(circle: circle) }
                }
            } else {
                ProgressView()
            }
        }
        .onAppear { circles.loadScreenshotFixtures() }
    }
}
#endif

private struct WamoriMigrationView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            BrandIconView(size: 112, showsShadow: true)
            VStack(spacing: AppSpacing.sm) {
                Text("HitoLogはWamoriになりました")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("これまでの投稿やプロフィールは、そのまま残っています。\nこれからは、大切な人との小さな「輪」で今日を残せます。")
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button("Wamoriをはじめる", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperCanvas())
    }
}

private enum InitialExperienceStep {
    case login
    case onboarding
}
