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
                    authSession.start()
                    appDelegate.installFirebaseMessagingDelegate()
                    await store.activateRemoteUser(
                        uid: authSession.currentUserID,
                        appleUserID: authSession.appleUserID,
                        displayName: authSession.displayName,
                        email: authSession.email
                    )
                    await pushService.configure(userID: authSession.currentUserID)
                }
                .onChange(of: authSession.currentUserID) { _, userID in
                    Task {
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
