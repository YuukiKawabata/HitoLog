import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var analytics: AnalyticsService
    let onFinish: () -> Void
    @State private var didTrackAppearance = false

    init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            BrandIconView(size: 84, showsShadow: false)

            VStack(spacing: AppSpacing.sm) {
                Text("大切な人と、今日をひとつずつ。")
                    .font(AppFont.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textPrimary)

                Text("2〜5人だけの「輪」で続ける、\n小さな交換日記です。")
                    .font(.body)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                OnboardingValueRow(systemImage: "person.2", text: "招待した人だけで輪をつくる")
                OnboardingValueRow(systemImage: "pencil", text: "今日のことを、輪ごとに1つ残す")
                OnboardingValueRow(systemImage: "bubble.right", text: "言葉やリアクションで静かにつながる")
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

            Spacer()

            Button(action: finish) {
                Label("Wamoriをはじめる", systemImage: "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppSpacing.lg)
        .background(PaperCanvas())
        .navigationTitle("Wamori")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didTrackAppearance else { return }
            didTrackAppearance = true
            analytics.capture("onboarding_started")
        }
    }

    private func finish() {
        analytics.capture("onboarding_completed")
        onFinish()
    }
}

private struct OnboardingValueRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.accent)
                .frame(width: 24)
        }
    }
}

private struct OnboardingPage: View {
    let icon: String?
    let kicker: String
    let title: String
    let text: String
    let detail: String

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 88, height: 88)
                    .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                            .stroke(AppColor.border, lineWidth: 0.7)
                    }
            } else {
                BrandIconView(size: 88)
            }

            VStack(spacing: AppSpacing.md) {
                SectionKicker(text: kicker)

                Text(title)
                    .font(AppFont.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textPrimary)
                Text(text)
                    .font(.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)

                InkDivider()
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()
        }
        .padding(AppSpacing.lg)
        .paperSurface()
        .padding(AppSpacing.lg)
    }
}

private struct OnboardingTopicPage: View {
    @Binding var selectedTopics: Set<String>

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "number.square.fill")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(AppColor.accent)
                .frame(width: 88, height: 88)
                .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 0.7)
                }

            VStack(spacing: AppSpacing.md) {
                SectionKicker(text: "ルーム".localized, systemImage: "person.3")

                Text("興味の小部屋を選ぶ")
                    .font(AppFont.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.textPrimary)
                Text("フォローした小部屋の投稿は、ホームのルームフィードに集まります。")
                    .font(.body)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                VStack(spacing: AppSpacing.sm) {
                    ForEach(StarterPackCategory.allCases) { category in
                        let isSelected = selectedTopics.contains(category.topic)
                        Button {
                            if isSelected {
                                selectedTopics.remove(category.topic)
                            } else {
                                selectedTopics.insert(category.topic)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: category.systemImage)
                                    .frame(width: 24)
                                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                                Text(category.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.bounce, value: isSelected)
                                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                            }
                            .foregroundStyle(AppColor.textPrimary)
                            .padding(AppSpacing.sm)
                            .background(
                                isSelected ? AppColor.accentSoft : AppColor.surface,
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .stroke(isSelected ? AppColor.accent.opacity(0.3) : AppColor.border, lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle(scale: 0.97))
                        .animation(.snappy(duration: 0.25), value: isSelected)
                        .accessibilityLabel(category.title)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }

                InkDivider()
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer()
        }
        .padding(AppSpacing.lg)
        .paperSurface()
        .padding(AppSpacing.lg)
    }
}
