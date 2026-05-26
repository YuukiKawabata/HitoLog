import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authSession: AuthSessionStore
    let onContinue: () -> Void
    @State private var isSigningIn = false

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
                        SectionKicker(text: "Human words in the AI age")

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

                VStack(spacing: AppSpacing.sm) {
                    if authSession.isFirebaseAuthAvailable {
                        SignInWithAppleButton(.signIn) { request in
                            authSession.prepareAppleRequest(request)
                            isSigningIn = true
                        } onCompletion: { result in
                            Task {
                                let didSignIn = await authSession.handleAppleCompletion(result)
                                await MainActor.run {
                                    isSigningIn = false
                                    if didSignIn {
                                        onContinue()
                                    }
                                }
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .disabled(isSigningIn)

                        #if DEBUG
                        LocalPreviewButton {
                            authSession.continueWithLocalPreview()
                            onContinue()
                        }
                        #endif
                    } else {
                        #if DEBUG
                        LocalPreviewButton {
                            authSession.continueWithLocalPreview()
                            onContinue()
                        }
                        #else
                        Label("サインインの準備が完了していません", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                        #endif
                    }

                    Text(authSession.isFirebaseAuthAvailable ? "Apple IDでサインインします。開発中はローカルプレビューも使えます。" : "サインイン設定を確認してください。")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(AppSpacing.lg)
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

#if DEBUG
private struct LocalPreviewButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("ローカルプレビューで開始", systemImage: "person.crop.circle.badge.checkmark")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
#endif
