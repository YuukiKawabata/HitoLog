import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    @EnvironmentObject private var analytics: AnalyticsService
    let onContinue: () -> Void
    @State private var isSigningIn = false
    @State private var appeared = false

    init(onContinue: @escaping () -> Void = {}) {
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            PaperCanvas()

            VStack(spacing: AppSpacing.xl) {
                Spacer()

                VStack(spacing: AppSpacing.lg) {
                    BrandIconView(size: 92)

                    VStack(spacing: AppSpacing.sm) {
                        SectionKicker(text: "親しい人だけの交換日記".localized)

                        Text("Wamori")
                            .font(AppFont.display)
                            .foregroundStyle(AppColor.textPrimary)

                        Text(AppConstants.copy)
                            .font(.body)
                            .foregroundStyle(AppColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    InkDivider()
                }
                .padding(AppSpacing.lg)
                .paperSurface()
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                VStack(spacing: AppSpacing.sm) {
                    if authSession.isFirebaseAuthAvailable {
                        SignInWithAppleButton(.signIn) { request in
                            authSession.prepareAppleRequest(request)
                            isSigningIn = true
                            analytics.capture("sign_in_started", properties: ["method": "apple"])
                        } onCompletion: { result in
                            Task {
                                let didSignIn = await authSession.handleAppleCompletion(result)
                                await MainActor.run {
                                    isSigningIn = false
                                    if didSignIn {
                                        analytics.capture("sign_in_completed", properties: ["method": "apple"])
                                        onContinue()
                                    } else {
                                        analytics.capture("sign_in_failed", properties: ["method": "apple"])
                                    }
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .disabled(isSigningIn)
                    }

                    Text(authSession.isFirebaseAuthAvailable
                        ? "Apple IDでサインインしてください。"
                        : "現在サインインを利用できません。しばらくしてからもう一度お試しください。")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(AppSpacing.lg)
        }
        .onAppear {
            analytics.capture("login_viewed")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
        .alert("サインインできません", isPresented: Binding(
            get: { authSession.errorMessage != nil },
            set: { if !$0 { authSession.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authSession.errorMessage ?? "")
        }
    }
}
