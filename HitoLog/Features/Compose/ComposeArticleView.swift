import PhotosUI
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
    @State private var freePreviewMode: EditorMode = .edit
    @State private var paidBodyMode: EditorMode = .edit
    @State private var isKeyboardVisible = false

    // 本文へのメディア差し込み
    @State private var mediaField: MediaField?
    @State private var isMediaPickerPresented = false
    @State private var mediaPickerItem: PhotosPickerItem?
    @State private var isInsertingMedia = false
    @State private var mediaErrorMessage: String?
    @State private var freePreviewInserter = TextInsertionController()
    @State private var paidBodyInserter = TextInsertionController()
    @State private var focusedField: MediaField?
    @FocusState private var isTitleFocused: Bool
    private let mediaUploadService = MediaUploadService()

    private enum EditorMode: Hashable { case edit, preview }
    private enum MediaField: Identifiable {
        case freePreview, paidBody
        var id: Self { self }

        var title: String {
            switch self {
            case .freePreview: return "無料プレビュー"
            case .paidBody: return "本文"
            }
        }

        var placeholder: String {
            switch self {
            case .freePreview: return "読者に届けたい冒頭の言葉を入力"
            case .paidBody: return "本文（省略可）"
            }
        }
    }
    let editingArticle: Article?
    let onSubmitted: (ArticleStatus) -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(editingArticle: Article? = nil, onSubmitted: @escaping (ArticleStatus) -> Void = { _ in }) {
        self.editingArticle = editingArticle
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    headerPanel
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                if isTitleFocused {
                                    Spacer()
                                    Button("完了") { isTitleFocused = false }
                                        .fontWeight(.semibold)
                                }
                            }
                        }

                    if hasSavedDraft {
                        Label("下書きを復元しました", systemImage: "tray.and.arrow.down.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.accent)
                    }

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
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.isEditing ? "記事を編集" : "記事")
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
                if !isKeyboardVisible {
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
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: isKeyboardVisible)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .onReceive(timer) { _ in
                viewModel.refreshMetricsDuration()
                saveDraft()
            }
            .onAppear { restoreOrLoadIfNeeded() }
            .photosPicker(
                isPresented: $isMediaPickerPresented,
                selection: $mediaPickerItem,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: mediaPickerItem) { _, newItem in
                guard let newItem, let field = mediaField else { return }
                handlePickedMedia(newItem, field: field)
            }
            .fullScreenCover(item: $focusedField) { field in
                FocusedEditorView(
                    title: field.title,
                    placeholder: field.placeholder,
                    text: binding(for: field),
                    onTextChanged: viewModel.recordChange(from:to:),
                    allowsMediaInsertion: true,
                    contentID: viewModel.workingArticleID
                )
                .environmentObject(store)
            }
        }
    }

    private func binding(for field: MediaField) -> Binding<String> {
        switch field {
        case .freePreview: return $viewModel.freePreviewBody
        case .paidBody: return $viewModel.paidBody
        }
    }

    private func requestMedia(for field: MediaField) {
        mediaErrorMessage = nil
        mediaField = field
        isMediaPickerPresented = true
    }

    private func inserter(for field: MediaField) -> TextInsertionController {
        switch field {
        case .freePreview: return freePreviewInserter
        case .paidBody: return paidBodyInserter
        }
    }

    private func handlePickedMedia(_ item: PhotosPickerItem, field: MediaField) {
        Task { @MainActor in
            isInsertingMedia = true
            mediaErrorMessage = nil
            defer {
                isInsertingMedia = false
                mediaPickerItem = nil
                mediaField = nil
            }

            do {
                let media = try await loadComposeMedia(
                    from: item,
                    store: store,
                    uploadService: mediaUploadService,
                    contentID: viewModel.workingArticleID
                )
                inserter(for: field).insert(InlineMedia.snippet(for: media))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                mediaErrorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
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
                .focused($isTitleFocused)
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
            HStack {
                SectionKicker(text: "無料プレビュー", systemImage: "eye")
                Spacer(minLength: AppSpacing.sm)
                expandButton(for: .freePreview)
                editorModePicker($freePreviewMode)
            }

            Text("誰でも読める冒頭部分。読者が続きを読みたくなる内容を書きましょう。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if freePreviewMode == .edit {
                    editorField(
                        text: $viewModel.freePreviewBody,
                        placeholder: "読者に届けたい冒頭の言葉を入力",
                        minHeight: 160,
                        inserter: freePreviewInserter,
                        onRequestMedia: { requestMedia(for: .freePreview) }
                    )
                } else {
                    markdownPreview(viewModel.freePreviewBody, minHeight: 160)
                }
            }
            .id(freePreviewMode)
            .transition(.opacity)

            if freePreviewMode == .edit {
                editorFootnote
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .animation(.easeInOut(duration: 0.2), value: freePreviewMode)
    }

    private var paidBodyPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                SectionKicker(text: "有料本文", systemImage: "lock.doc")
                Spacer(minLength: AppSpacing.sm)
                expandButton(for: .paidBody)
                editorModePicker($paidBodyMode)
            }

            Text("有料記事の場合、購入者のみが読める部分です。無料記事は全文公開されます。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if paidBodyMode == .edit {
                    editorField(
                        text: $viewModel.paidBody,
                        placeholder: "本文（省略可）",
                        minHeight: 240,
                        inserter: paidBodyInserter,
                        onRequestMedia: { requestMedia(for: .paidBody) }
                    )
                } else {
                    markdownPreview(viewModel.paidBody, minHeight: 240)
                }
            }
            .id(paidBodyMode)
            .transition(.opacity)

            if paidBodyMode == .edit {
                editorFootnote
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .animation(.easeInOut(duration: 0.2), value: paidBodyMode)
    }

    // MARK: - エディタ / プレビュー 共通部品

    private func expandButton(for field: MediaField) -> some View {
        Button {
            focusedField = field
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(field.title)を全画面で書く")
    }

    private func editorModePicker(_ mode: Binding<EditorMode>) -> some View {
        Picker("表示モード", selection: mode) {
            Text("編集").tag(EditorMode.edit)
            Text("プレビュー").tag(EditorMode.preview)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 168)
    }

    private func editorField(
        text: Binding<String>,
        placeholder: String,
        minHeight: CGFloat,
        inserter: TextInsertionController,
        onRequestMedia: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            NoPasteTextViewRepresentable(
                text: text,
                onTextChanged: viewModel.recordChange(from:to:),
                accessory: .formatting,
                onRequestMediaInsert: onRequestMedia,
                insertionController: inserter
            )
            .frame(minHeight: minHeight)
            .padding(AppSpacing.sm)

            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(AppColor.placeholder)
                    .padding(.horizontal, AppSpacing.md + 4)
                    .padding(.vertical, AppSpacing.md + 2)
            }
        }
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private var editorFootnote: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                Label("ペースト不可", systemImage: "doc.on.clipboard")
                Label("写真・動画はツールバーの ⊕ から差し込めます", systemImage: "photo.badge.plus")
            }
            .font(.caption)
            .foregroundStyle(AppColor.textSecondary)

            if isInsertingMedia {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("メディアを挿入しています")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            if let mediaErrorMessage {
                Label(mediaErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func markdownPreview(_ text: String, minHeight: CGFloat) -> some View {
        Group {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("プレビューする内容がありません")
                    .font(.body)
                    .foregroundStyle(AppColor.placeholder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownBodyView(markdown: text)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
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
                                .padding(.vertical, AppSpacing.xs)
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

        let (article, paidBody) = viewModel.makeArticle(id: viewModel.workingArticleID, using: store.currentUser, status: status)
        if viewModel.isEditing {
            store.updateArticle(article, paidBody: paidBody)
        } else {
            store.insertArticle(article, paidBody: paidBody)
            clearDraft()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSubmitted(status)
        dismiss()
    }

    private func restoreOrLoadIfNeeded() {
        guard !didRestoreDraft else { return }
        didRestoreDraft = true

        if let editingArticle {
            viewModel.load(article: editingArticle, paidBody: "")
            Task {
                if let body = try? await store.loadArticleBody(articleID: editingArticle.id), !body.isEmpty {
                    viewModel.paidBody = body
                }
            }
            return
        }

        didRestoreExistingDraft = !draftPayload.isEmpty
        viewModel.restoreDraft(from: draftPayload)
    }

    private func saveDraft() {
        // 既存記事の編集中は、新規作成用の自動下書き(@AppStorage)を上書きしない。
        guard !viewModel.isEditing else { return }
        draftPayload = viewModel.encodedDraft()
    }

    private func clearDraft() {
        viewModel.clearDraft()
        draftPayload = ""
        didRestoreExistingDraft = false
    }
}
