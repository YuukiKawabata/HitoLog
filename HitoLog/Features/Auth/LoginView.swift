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
                        SectionKicker(text: "AI時代の人間の言葉".localized)

                        Text("HitoLog")
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

                        LocalPreviewButton {
                            analytics.capture("sample_mode_started")
                            authSession.continueWithLocalPreview()
                            onContinue()
                        }
                    } else {
                        LocalPreviewButton {
                            analytics.capture("sample_mode_started")
                            authSession.continueWithLocalPreview()
                            onContinue()
                        }
                    }

                    Text(authSession.isFirebaseAuthAvailable ? "Apple IDでサインインします。まず見るだけならサンプルデータでも確認できます。" : "サンプルデータで機能を確認できます。")
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

private struct LocalPreviewButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("サンプルデータで試す", systemImage: "person.crop.circle.badge.checkmark")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
