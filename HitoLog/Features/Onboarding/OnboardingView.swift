import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var selection = 0

    init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            TabView(selection: $selection) {
                OnboardingPage(
                    icon: nil,
                    title: "自分の言葉で書く",
                    text: "HitoLogでは、投稿欄で入力した言葉を大切にします。",
                    detail: "貼り付けではなく、その場で考えながら書く体験を中心にします。"
                )
                .tag(0)

                OnboardingPage(
                    icon: "doc.on.clipboard",
                    title: "ペーストできない投稿欄",
                    text: "投稿作成ではコピー＆ペーストを使えません。",
                    detail: "音声入力や通常の編集は残しつつ、量産投稿を入りにくくします。"
                )
                .tag(1)

                OnboardingPage(
                    icon: "checkmark.seal",
                    title: "本人入力バッジ",
                    text: "入力時間、編集、削除の流れからHuman Checkを行います。",
                    detail: "点数で人を評価するのではなく、読む人に小さな信頼感を渡します。"
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: next) {
                Label(selection == 2 ? "はじめる" : "次へ", systemImage: selection == 2 ? "arrow.right.circle.fill" : "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(AppColor.groupedBackground)
        .navigationTitle("HitoLog")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func next() {
        if selection < 2 {
            withAnimation(.snappy) {
                selection += 1
            }
        } else {
            onFinish()
        }
    }
}

private struct OnboardingPage: View {
    let icon: String?
    let title: String
    let text: String
    let detail: String

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 88, height: 88)
                    .background(AppColor.accent.opacity(0.12), in: Circle())
            } else {
                BrandIconView(size: 88)
            }

            VStack(spacing: AppSpacing.md) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(text)
                    .font(.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()
        }
        .padding(AppSpacing.lg)
    }
}
