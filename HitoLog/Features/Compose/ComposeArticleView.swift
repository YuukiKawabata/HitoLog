import SwiftUI

struct ComposeArticleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var viewModel = ComposeArticleViewModel()
    @AppStorage("composeArticleDraftPayload") private var draftPayload = ""
    @State private var didRestoreDraft = false
    @State private var didRestoreExistingDraft = false
    @State private var isShowingDeleteDraftConfirmation = false
    @State private var isSubmitting = false
    let onSubmitted: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(onSubmitted: @escaping () -> Void = {}) {
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    headerPanel
                    titlePanel
                    freePreviewPanel
                    paidBodyPanel
                    pricePanel
                    topicRoomPreviewPanel
                    commentPermissionPanel
                    humanCheckPanel
                    metricsPanel
                }
                .padding(AppSpacing.md)
            }
            .background(PaperCanvas())
            .navigationTitle("記事")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        saveDraft()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("公開") {
                        submit(status: .published)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .confirmationDialog("下書きを削除しますか？", isPresented: $isShowingDeleteDraftConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) { clearDraft() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("削除した下書きは元に戻せません。")
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: AppSpacing.sm) {
                    Button { submit(status: .draft) } label: {
                        Label("下書き保存", systemImage: "tray")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!canSubmit || isSubmitting)

                    Button { submit(status: .published) } label: {
                        submitButtonLabel
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(.ultraThinMaterial)
            }
            .onReceive(timer) { _ in
                viewModel.refreshMetricsDuration()
                saveDraft()
            }
            .onAppear { restoreDraftIfNeeded() }
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "Article Desk", systemImage: "doc.text")

            Text("時間をかけて書いた言葉を残す")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)

            Text("Human Check 付きで、あなたの記事を公開できます。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            InkDivider()
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var titlePanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionKicker(text: "Title", systemImage: "textformat")

            TextField("記事のタイトル", text: $viewModel.title, axis: .vertical)
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1...3)
                .padding(AppSpacing.sm)
                .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

            Text("\(viewModel.title.count)/100")
                .font(.caption)
                .foregroundStyle(viewModel.title.count > 90 ? AppColor.warning : AppColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var freePreviewPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionKicker(text: "無料プレビュー", systemImage: "eye")

            Text("誰でも読める冒頭部分。読者が続きを読みたくなる内容を書きましょう。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                NoPasteTextViewRepresentable(
                    text: $viewModel.freePreviewBody,
                    onTextChanged: viewModel.recordChange(from:to:)
                )
                .frame(minHeight: 160)
                .padding(AppSpacing.sm)

                if viewModel.freePreviewBody.isEmpty {
                    Text("読者に届けたい冒頭の言葉を入力")
                        .font(.body)
                        .foregroundStyle(AppColor.placeholder)
                        .padding(.horizontal, AppSpacing.md + 4)
                        .padding(.vertical, AppSpacing.md + 2)
                }
            }
            .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

            Label("ペースト不可", systemImage: "doc.on.clipboard")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var paidBodyPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionKicker(text: "有料本文", systemImage: "lock.doc")

            Text("有料記事の場合、購入者のみが読める部分です。無料記事は全文公開されます。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                NoPasteTextViewRepresentable(
                    text: $viewModel.paidBody,
                    onTextChanged: viewModel.recordChange(from:to:)
                )
                .frame(minHeight: 240)
                .padding(AppSpacing.sm)

                if viewModel.paidBody.isEmpty {
                    Text("本文（省略可）")
                        .font(.body)
                        .foregroundStyle(AppColor.placeholder)
                        .padding(.horizontal, AppSpacing.md + 4)
                        .padding(.vertical, AppSpacing.md + 2)
                }
            }
            .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))

            Label("ペースト不可", systemImage: "doc.on.clipboard")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var pricePanel: some View {
        let canSetPaid = store.isCreatorEligible && viewModel.canSetPaidPrice

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "価格", systemImage: "yensign.circle")

            if !canSetPaid {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("有料記事の資格条件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)

                    ForEach(store.creatorEligibilityDetail, id: \.label) { item in
                        Label(item.label, systemImage: item.met ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(item.met ? AppColor.accent : AppColor.textSecondary)
                    }

                    Label(
                        viewModel.canSetPaidPrice ? "この記事のHuman Check: 本人入力 ✓" : "この記事のHuman Check: 本人入力が必要です",
                        systemImage: viewModel.canSetPaidPrice ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(viewModel.canSetPaidPrice ? AppColor.accent : AppColor.textSecondary)
                }
                .padding(AppSpacing.sm)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            Picker("価格", selection: $viewModel.price) {
                ForEach(ArticlePrice.allCases, id: \.self) { price in
                    Text(price.displayText)
                        .tag(price)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canSetPaid)
            .opacity(canSetPaid ? 1 : 0.5)

            Text(viewModel.price == .free
                 ? "全文を無料で公開します。"
                 : "プレビュー部分を無料公開し、本文は\(viewModel.price.displayText)で販売します。App Store 手数料（30%）が差し引かれます。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    @ViewBuilder
    private var topicRoomPreviewPanel: some View {
        let topics = TopicExtractor.topics(in: "\(viewModel.title) \(viewModel.freePreviewBody)")
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionKicker(text: "Topic Rooms", systemImage: "number.square")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(topics, id: \.self) { topic in
                            Label("#\(topic)", systemImage: "number")
                                .font(.caption.weight(.semibold))
                                .padding(.vertical, 7)
                                .padding(.horizontal, AppSpacing.sm)
                                .background(AppColor.accentSoft, in: Capsule())
                                .foregroundStyle(AppColor.accent)
                        }
                    }
                }
            }
            .padding(AppSpacing.md)
            .paperSurface()
        }
    }

    private var commentPermissionPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "Comments", systemImage: "bubble.right")

            Picker("コメント", selection: $viewModel.commentPermission) {
                ForEach(CommentPermission.allCases) { permission in
                    Text(permission.displayText).tag(permission)
                }
            }
            .pickerStyle(.segmented)

            Label(viewModel.commentPermission.detailText, systemImage: viewModel.commentPermission.systemImage)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var humanCheckPanel: some View {
        HumanSignalStrip(
            title: viewModel.humanCheckText,
            detail: "入力の速度と編集の揺らぎを、読む人への小さな署名にします。",
            systemImage: viewModel.metrics.suspiciousBulkInputCount == 0 ? "checkmark.seal.fill" : "clock.badge.questionmark",
            tint: viewModel.metrics.suspiciousBulkInputCount == 0 ? AppColor.accent : AppColor.warning
        )
        .padding(AppSpacing.md)
        .paperSurface()
    }

    private var metricsPanel: some View {
        HStack(spacing: AppSpacing.sm) {
            PaperMetricTile(title: "入力時間", value: viewModel.metrics.durationText, systemImage: "timer")
            PaperMetricTile(title: "編集", value: "\(viewModel.metrics.editCount)", systemImage: "pencil")
            PaperMetricTile(title: "削除", value: "\(viewModel.metrics.deleteCount)", systemImage: "delete.left")
        }
    }

    @ViewBuilder
    private var submitButtonLabel: some View {
        if isSubmitting {
            HStack(spacing: AppSpacing.sm) {
                ProgressView().tint(AppColor.background)
                Text("公開中")
            }
        } else {
            Label("この記事を公開する", systemImage: "paperplane.fill")
        }
    }

    private var canSubmit: Bool {
        !store.currentUser.isSuspended && viewModel.canSubmit && !isSubmitting
    }

    private var hasSavedDraft: Bool {
        didRestoreExistingDraft && viewModel.hasDraft
    }

    private func submit(status: ArticleStatus) {
        Task { await submitArticle(status: status) }
    }

    @MainActor
    private func submitArticle(status: ArticleStatus) async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let (article, paidBody) = viewModel.makeArticle(using: store.currentUser, status: status)
        store.insertArticle(article, paidBody: paidBody)
        clearDraft()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSubmitted()
        dismiss()
    }

    private func restoreDraftIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true
        didRestoreExistingDraft = !draftPayload.isEmpty
        viewModel.restoreDraft(from: draftPayload)
    }

    private func saveDraft() {
        draftPayload = viewModel.encodedDraft()
    }

    private func clearDraft() {
        viewModel.clearDraft()
        draftPayload = ""
        didRestoreExistingDraft = false
    }
}
