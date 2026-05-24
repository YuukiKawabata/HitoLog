import Foundation

enum AppRoute: Hashable {
    case login
    case onboarding
    case profileSetup
    case timeline
    case postDetail(String)
    case profile(String)
    case settings
}

enum AppSessionState {
    case signedOut
    case onboarding
    case ready
}

