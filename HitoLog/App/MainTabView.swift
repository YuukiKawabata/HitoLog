import SwiftUI

struct MainTabView: View {
    @State private var isShowingCompose = false
    @State private var isShowingPostToast = false
    @State private var celebrationToken = 0

    var body: some View {
        TabView {
            NavigationStack {
                TimelineView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }

            NavigationStack {
                ComposeEntryView {
                    isShowingCompose = true
                }
            }
            .tabItem {
                Label("投稿", systemImage: "square.and.pencil")
            }

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("プロフィール", systemImage: "person.crop.circle")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("設定", systemImage: "gearshape")
            }
        }
        .tint(AppColor.accent)
        .sheet(isPresented: $isShowingCompose) {
            ComposePostView {
                showPostToast()
            }
        }
        .overlay(alignment: .top) {
            if isShowingPostToast {
                PostSubmittedToast()
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isShowingPostToast {
                PostSubmittedCelebration(token: celebrationToken)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: isShowingPostToast)
    }

    private func showPostToast() {
        celebrationToken += 1
        let currentToken = celebrationToken
        isShowingPostToast = true
        Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            await MainActor.run {
                if celebrationToken == currentToken {
                    isShowingPostToast = false
                }
            }
        }
    }
}

private struct PostSubmittedCelebration: View {
    let token: Int
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.accent.opacity(isAnimating ? 0 : 0.24), lineWidth: 2)
                .frame(width: isAnimating ? 172 : 72, height: isAnimating ? 172 : 72)

            VStack(spacing: AppSpacing.sm) {
                BrandIconView(size: 58)

                VStack(spacing: 2) {
                    Text("投稿しました")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("タイムラインに反映されました")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }
            .shadow(color: AppColor.shadow, radius: 18, y: 10)
        }
        .onAppear {
            isAnimating = false
            withAnimation(.easeOut(duration: 0.9)) {
                isAnimating = true
            }
        }
        .id(token)
    }
}

private struct PostSubmittedToast: View {
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.accent)
            Text("投稿しました")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .shadow(color: AppColor.shadow, radius: 12, y: 6)
    }
}

private struct ComposeEntryView: View {
    let onComposeTap: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {
                BrandIconView(size: 78)

                SectionKicker(text: "Draft Desk", systemImage: "pencil.line")

                Text("いま、あなたの言葉で。")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("一息ぶんの沈黙も、書き直した跡も、あなたの言葉の一部として残ります。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                InkDivider()
            }
            .padding(AppSpacing.lg)
            .paperSurface()

            Button(action: onComposeTap) {
                Label("投稿を書く", systemImage: "pencil")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperCanvas())
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
    }
}
