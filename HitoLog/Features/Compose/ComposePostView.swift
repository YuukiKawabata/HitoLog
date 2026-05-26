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

                    HumanCheckPanel(metrics: viewModel.metrics, statusText: viewModel.humanCheckText)

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
        HumanSignalStrip(
            title: statusText,
            detail: "入力の速度と編集の揺らぎを、読む人への小さな署名にします。",
            systemImage: metrics.suspiciousBulkInputCount == 0 ? "checkmark.seal.fill" : "clock.badge.questionmark",
            tint: metrics.suspiciousBulkInputCount == 0 ? AppColor.accent : AppColor.warning
        )
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
