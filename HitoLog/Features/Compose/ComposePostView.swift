import SwiftUI

struct ComposePostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    @StateObject private var viewModel = ComposePostViewModel()
    @AppStorage("composePostDraftPayload") private var draftPayload = ""
    @State private var didRestoreDraft = false
    @State private var didRestoreExistingDraft = false
    @State private var isShowingDeleteDraftConfirmation = false
    let onSubmitted: () -> Void
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(onSubmitted: @escaping () -> Void = {}) {
        self.onSubmitted = onSubmitted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("いま、あなたの言葉で。")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppColor.textPrimary)

                        Text("貼り付けではなく、ここで考えながら書いた言葉だけを投稿します。")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if hasSavedDraft {
                        Label("下書きを復元しました", systemImage: "tray.and.arrow.down.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.accent)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ZStack(alignment: .topLeading) {
                            NoPasteTextViewRepresentable(
                                text: $viewModel.text,
                                onTextChanged: viewModel.recordChange(from:to:)
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
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                                .stroke(AppColor.border, lineWidth: 0.5)
                        }

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

                    HumanCheckPanel(metrics: viewModel.metrics, statusText: viewModel.humanCheckText)

                    HStack(spacing: AppSpacing.sm) {
                        MetricPill(title: "入力時間", value: viewModel.metrics.durationText)
                        MetricPill(title: "編集", value: "\(viewModel.metrics.editCount)")
                        MetricPill(title: "削除", value: "\(viewModel.metrics.deleteCount)")
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppColor.groupedBackground)
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
                    .disabled(!viewModel.canSubmit)
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
                Button(action: submit) {
                    Label("この言葉を投稿する", systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!viewModel.canSubmit)
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.sm)
                .background(.ultraThinMaterial)
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
        }
    }

    private func submit() {
        let post = viewModel.makePost(using: store.currentUser, recentPostCount: store.recentPostCount)
        store.insert(post)
        clearDraft()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSubmitted()
        dismiss()
    }

    private var hasSavedDraft: Bool {
        didRestoreExistingDraft && viewModel.hasDraft
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
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private struct HumanCheckPanel: View {
    let metrics: TypingMetrics
    let statusText: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: metrics.suspiciousBulkInputCount == 0 ? "checkmark.seal.fill" : "clock.badge.questionmark")
                .font(.title3)
                .foregroundStyle(metrics.suspiciousBulkInputCount == 0 ? AppColor.accent : AppColor.warning)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text("入力時間、編集、削除の流れをもとに本人入力らしさを判定します。")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
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
