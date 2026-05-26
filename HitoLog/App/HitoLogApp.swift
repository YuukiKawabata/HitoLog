import SwiftUI

@main
@MainActor
struct HitoLogApp: App {
    @UIApplicationDelegateAdaptor(HitoLogAppDelegate.self) private var appDelegate
    @StateObject private var authSession = AuthSessionStore()
    @StateObject private var store = AppDataStore()
    @StateObject private var pushService = PushNotificationService.shared
    @AppStorage("hasCompletedInitialExperience") private var hasCompletedInitialExperience = false

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            RootView(hasCompletedInitialExperience: $hasCompletedInitialExperience)
                .environmentObject(store)
                .environmentObject(authSession)
                .environmentObject(pushService)
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
    @EnvironmentObject private var authSession: AuthSessionStore
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
    }
}

private enum InitialExperienceStep {
    case login
    case onboarding
}
