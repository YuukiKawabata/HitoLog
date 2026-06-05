import PhotosUI
import SwiftUI

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var viewModel = ComposePostViewModel()
    @AppStorage("composePostDraftPayload") private var draftPayload = ""
    @State private var didRestoreDraft = false
    @State private var didRestoreExistingDraft = false
    @State private var isShowingDeleteDraftConfirmation = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedMediaItems: [ComposeMediaItem] = []
    @State private var commentPermission: CommentPermission = .everyone
    @State private var isLoadingMedia = false
    @State private var isSubmitting = false
    @State private var mediaErrorMessage: String?
    @State private var isKeyboardVisible = false
    @State private var isFocusedEditing = false
    let onSubmitted: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let mediaUploadService = MediaUploadService()

    init(onSubmitted: @escaping () -> Void = {}) {
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        SectionKicker(text: "Draft Desk", systemImage: "pencil.line")

                        Text("いま、あなたの言葉で。")
                            .font(AppFont.title)
                            .foregroundStyle(AppColor.textPrimary)

                        Text("考えて、消して、また書く。その時間ごと投稿に残します。")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        InkDivider()
                    }
                    .padding(AppSpacing.md)
                    .paperSurface()

                    if hasSavedDraft {
                        Label("下書きを復元しました", systemImage: "tray.and.arrow.down.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.accent)
                    }

                    if store.currentUser.isSuspended {
                        Label("このアカウントは現在投稿できません。", systemImage: "person.crop.circle.badge.xmark")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.warning)
                            .padding(AppSpacing.md)
                            .paperSurface()
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            Spacer()
                            Button {
                                isFocusedEditing = true
                            } label: {
                                Label("全画面で書く", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.accent)
                            }
                            .accessibilityLabel("全画面で書く")
                        }

                        ZStack(alignment: .topLeading) {
                            NoPasteTextViewRepresentable(
                                text: $viewModel.text,
                                onTextChanged: viewModel.recordChange(from:to:),
                                accessory: .formatting
                            )
                            .frame(minHeight: 300)
                            .padding(AppSpacing.sm)

                            if viewModel.text.isEmpty {
                                Text("思っていることを、そのまま入力")
                                    .font(.body)
                                    .foregroundStyle(AppColor.placeholder)
                                    .padding(.horizontal, AppSpacing.md + 4)
                                    .padding(.vertical, AppSpacing.md + 2)
                            }
                        }
                        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                        .paperSurface(shadow: false)

                        VStack(spacing: AppSpacing.xs) {
                            ProgressView(value: min(Double(viewModel.text.count), Double(AppConstants.maxPostLength)), total: Double(AppConstants.maxPostLength))
                                .tint(viewModel.isNearLimit ? AppColor.warning : AppColor.accent)

                            HStack {
                                Label("ペースト不可", systemImage: "doc.on.clipboard")
                                Spacer()
                            Text(viewModel.characterCountText)
                                    .foregroundStyle(viewModel.isNearLimit ? AppColor.warning : AppColor.textSecondary)
                            }
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        }

                        if viewModel.hasDraft {
                            Button(role: .destructive) {
                                isShowingDeleteDraftConfirmation = true
                            } label: {
                                Label("下書きを削除", systemImage: "trash")
                            }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderless)
                        }
                    }

                    mediaAttachmentPanel

                    topicRoomPreviewPanel

                    commentPermissionPanel

                    HumanCheckPanel(
                        metrics: viewModel.metrics,
                        statusText: viewModel.humanCheckText,
                        aiAssisted: $viewModel.aiAssisted
                    )

                    HStack(spacing: AppSpacing.sm) {
                        PaperMetricTile(title: "入力時間", value: viewModel.metrics.durationText, systemImage: "timer")
                        PaperMetricTile(title: "編集", value: "\(viewModel.metrics.editCount)", systemImage: "pencil")
                        PaperMetricTile(title: "削除", value: "\(viewModel.metrics.deleteCount)", systemImage: "delete.left")
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(PaperCanvas())
            .navigationTitle("投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        saveDraft()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("投稿") {
                        submit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .confirmationDialog("下書きを削除しますか？", isPresented: $isShowingDeleteDraftConfirmation, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    clearDraft()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("削除した下書きは元に戻せません。")
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    Button(action: submit) {
                        submitButtonLabel
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSubmit)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.sm)
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
            .onAppear {
                restoreDraftIfNeeded()
            }
            .onChange(of: viewModel.text) { _, _ in
                saveDraft()
            }
            .onChange(of: viewModel.metrics) { _, _ in
                saveDraft()
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                appendSelectedMedia(from: newItems)
            }
            .fullScreenCover(isPresented: $isFocusedEditing) {
                FocusedEditorView(
                    title: "投稿",
                    placeholder: "思っていることを、そのまま入力",
                    text: $viewModel.text,
                    onTextChanged: viewModel.recordChange(from:to:)
                )
                .environmentObject(store)
            }
        }
    }

    private func submit() {
        Task {
            await submitPost()
        }
    }

    private var hasSavedDraft: Bool {
        didRestoreExistingDraft && viewModel.hasDraft
    }

    private var canSubmit: Bool {
        !store.currentUser.isSuspended && viewModel.canSubmit && !isLoadingMedia && !isSubmitting
    }

    private var remainingMediaSlots: Int {
        max(AppConstants.maxPostMediaItems - selectedMediaItems.count, 0)
    }

    @ViewBuilder
    private var submitButtonLabel: some View {
        if isSubmitting {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(AppColor.background)
                Text("投稿中")
            }
        } else {
            Label("この言葉を投稿する", systemImage: "paperplane.fill")
        }
    }

    private var mediaAttachmentPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .center, spacing: AppSpacing.sm) {
                SectionKicker(text: "Media", systemImage: "photo.on.rectangle.angled")

                Spacer(minLength: 0)

                Text("\(selectedMediaItems.count)/\(AppConstants.maxPostMediaItems)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: max(remainingMediaSlots, 1),
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("追加", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(remainingMediaSlots == 0 || isLoadingMedia || isSubmitting)
            }

            if selectedMediaItems.isEmpty {
                Text("写真と動画を最大4件まで一緒に添付できます。本文は必須です。")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(selectedMediaItems) { item in
                            ComposeMediaPreviewTile(item: item) {
                                selectedMediaItems.removeAll { $0.id == item.id }
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
            }

            if isLoadingMedia {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("メディアを読み込んでいます")
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
        .padding(AppSpacing.md)
        .paperSurface()
    }

    @ViewBuilder
    private var topicRoomPreviewPanel: some View {
        let topics = TopicExtractor.topics(in: viewModel.text)
        if !topics.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionKicker(text: "Topic Rooms", systemImage: "number.square")

                Text("本文のハッシュタグから、投稿先の小部屋が自動で決まります。")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)

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

            Picker("コメント", selection: $commentPermission) {
                ForEach(CommentPermission.allCases) { permission in
                    Text(permission.displayText).tag(permission)
                }
            }
            .pickerStyle(.segmented)

            Label(commentPermission.detailText, systemImage: commentPermission.systemImage)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }

    @MainActor
    private func submitPost() async {
        guard canSubmit else { return }

        isSubmitting = true
        mediaErrorMessage = nil
        defer { isSubmitting = false }

        do {
            let postID = UUID().uuidString
            let mediaItems: [PostMedia]
            if selectedMediaItems.isEmpty {
                mediaItems = []
            } else if store.isRemoteSyncEnabled {
                mediaItems = try await mediaUploadService.upload(
                    selectedMediaItems,
                    userID: store.currentUser.id,
                    postID: postID
                )
            } else {
                mediaItems = try mediaUploadService.localMediaItems(from: selectedMediaItems)
            }

            let post = viewModel.makePost(
                id: postID,
                using: store.currentUser,
                recentPostCount: store.recentPostCount,
                mediaItems: mediaItems,
                commentPermission: commentPermission
            )
            store.insert(post)
            clearDraft()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSubmitted()
            dismiss()
        } catch {
            mediaErrorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func appendSelectedMedia(from items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        Task { @MainActor in
            let allowedItems = Array(items.prefix(remainingMediaSlots))
            selectedPhotoItems = []
            guard !allowedItems.isEmpty else {
                mediaErrorMessage = "写真と動画は最大\(AppConstants.maxPostMediaItems)件まで添付できます。"
                return
            }

            isLoadingMedia = true
            mediaErrorMessage = items.count > allowedItems.count
                ? "写真と動画は最大\(AppConstants.maxPostMediaItems)件まで添付できます。"
                : nil
            defer { isLoadingMedia = false }

            do {
                for item in allowedItems {
                    let mediaItem = try await ComposeMediaItem.load(from: item)
                    selectedMediaItems.append(mediaItem)
                }
            } catch {
                mediaErrorMessage = error.localizedDescription
            }
        }
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
        selectedMediaItems = []
        selectedPhotoItems = []
        commentPermission = .everyone
        mediaErrorMessage = nil
        draftPayload = ""
        didRestoreExistingDraft = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct ComposeMediaPreviewTile: View {
    let item: ComposeMediaItem
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                if let previewImage = item.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    AppColor.surface
                    Image(systemName: item.type == .video ? "film" : "photo")
                        .foregroundStyle(AppColor.textSecondary)
                }

                if item.type == .video {
                    Label(durationText, systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(.black.opacity(0.56), in: Capsule())
                        .padding(AppSpacing.xs)
                }
            }
            .frame(width: 108, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.background)
                    .frame(width: 24, height: 24)
                    .background(AppColor.textPrimary.opacity(0.82), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    private var durationText: String {
        guard let durationMs = item.durationMs else { return "0:00" }
        let seconds = max(durationMs / 1_000, 0)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct HumanCheckPanel: View {
    let metrics: TypingMetrics
    let statusText: String
    /// AI併用の開示トグル。投稿画面でのみ渡す（記事など未対応の画面では nil）。
    var aiAssisted: Binding<Bool>? = nil

    private var isClean: Bool {
        metrics.suspiciousBulkInputCount == 0
    }

    /// 一括入力の疑いがあり、かつ開示トグルを扱える画面か。
    private var showsDisclosure: Bool {
        aiAssisted != nil && metrics.suspiciousBulkInputCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HumanSignalStrip(
                title: statusText,
                detail: "入力の速度と編集の揺らぎを、読む人への小さな署名にします。",
                systemImage: isClean ? "checkmark.seal.fill" : "clock.badge.questionmark",
                tint: isClean ? AppColor.accent : AppColor.warning
            )

            if showsDisclosure, let aiAssisted {
                Divider()
                    .background(AppColor.border)

                Toggle(isOn: aiAssisted) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Label("AIの助けを借りた", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("正直に開示すれば、投稿に「AI併用」と表示され信頼度は下がりません。隠したまま投稿すると信頼度が下がります。")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(AppColor.accent)
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
