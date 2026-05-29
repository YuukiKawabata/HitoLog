import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppDataStore
    let onFinish: () -> Void
    @State private var selection = 0
    @State private var selectedTopics = Set(StarterPackCategory.allCases.map(\.topic).prefix(2))

    init(onFinish: @escaping () -> Void = {}) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            TabView(selection: $selection) {
                OnboardingPage(
                    icon: nil,
                    kicker: "First Note",
                    title: "自分の言葉で書く",
                    text: "HitoLogでは、投稿欄で入力した言葉を大切にします。",
                    detail: "貼り付けではなく、その場で考えながら書く体験を中心にします。"
                )
                .tag(0)

                OnboardingPage(
                    icon: "doc.on.clipboard",
                    kicker: "No Paste",
                    title: "ペーストできない投稿欄",
                    text: "投稿作成ではコピー＆ペーストを使えません。",
                    detail: "音声入力や通常の編集は残しつつ、量産投稿を入りにくくします。"
                )
                .tag(1)

                OnboardingPage(
                    icon: "checkmark.seal",
                    kicker: "Human Check",
                    title: "本人入力バッジ",
                    text: "入力時間、編集、削除の流れからHuman Checkを行います。",
                    detail: "点数で人を評価するのではなく、読む人に小さな信頼感を渡します。"
                )
                .tag(2)

                OnboardingTopicPage(selectedTopics: $selectedTopics)
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: next) {
                Label(selection == 3 ? "はじめる" : "次へ", systemImage: selection == 3 ? "arrow.right.circle.fill" : "arrow.right")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .background(PaperCanvas())
        .navigationTitle("HitoLog")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func next() {
        if selection < 3 {
            withAnimation(.snappy) {
                selection += 1
            }
        } else {
            for topic in selectedTopics {
                if !store.isFollowingTopic(topic) {
                    store.toggleTopicFollow(topic: topic)
                }
            }
            onFinish()
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
                SectionKicker(text: "Topic Rooms", systemImage: "person.3")

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
