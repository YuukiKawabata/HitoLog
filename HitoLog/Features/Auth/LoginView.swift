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
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            VStack(spacing: AppSpacing.lg) {
                BrandIconView(size: 92)

                Text("HitoLog")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppColor.textPrimary)

                Text(AppConstants.copy)
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

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
                } else {
                    #if DEBUG
                    Button {
                        authSession.continueWithLocalPreview()
                        onContinue()
                    } label: {
                        Label("ローカルプレビューで開始", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    #else
                    Label("サインインの準備が完了していません", systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                    #endif
                }

                Text(authSession.isFirebaseAuthAvailable ? "Apple IDでサインインします。" : "サインイン設定を確認してください。")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(AppSpacing.lg)
        .background(AppColor.groupedBackground)
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
