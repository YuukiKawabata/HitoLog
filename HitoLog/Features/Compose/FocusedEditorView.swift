import PhotosUI
import SwiftUI

/// 選択したメディアをアップロード（リモート時）または data/file URL 化（ローカル時）し、`PostMedia` を返す。
/// 記事エディタ・全画面エディタなど、本文へインライン挿入する各所で共有する。
@MainActor
func loadComposeMedia(
    from item: PhotosPickerItem,
    store: AppDataStore,
    uploadService: MediaUploadService,
    contentID: String
) async throws -> PostMedia {
    let composeItem = try await ComposeMediaItem.load(from: item)
    if store.isRemoteSyncEnabled {
        guard let media = try await uploadService.upload(
            [composeItem],
            userID: store.currentUser.id,
            postID: contentID
        ).first else {
            throw MediaUploadError.uploadFailed
        }
        return media
    } else {
        guard let media = try uploadService.localMediaItems(from: [composeItem]).first else {
            throw MediaUploadError.uploadFailed
        }
        return media
    }
}

/// 設定パネルに邪魔されず本文だけに集中して書くための全画面エディタ。
/// 編集／プレビュー切替・Markdown ツールバーを備え、`allowsMediaInsertion` 有効時のみ
/// ツールバーからの写真・動画インライン挿入を許可する（投稿では無効、記事では有効）。
struct FocusedEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore

    let title: String
    let placeholder: String
    @Binding var text: String
    var onTextChanged: (String, String) -> Void
    var allowsMediaInsertion = false
    var contentID = ""

    @State private var mode: Mode = .edit
    @State private var inserter = TextInsertionController()
    @State private var isMediaPickerPresented = false
    @State private var mediaPickerItem: PhotosPickerItem?
    @State private var isInsertingMedia = false
    @State private var mediaErrorMessage: String?
    private let uploadService = MediaUploadService()

    private enum Mode: Hashable { case edit, preview }

    var body: some View {
        NavigationStack {
            Group {
                if mode == .edit {
                    editor
                } else {
                    preview
                }
            }
            .background(PaperCanvas())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("表示モード", selection: $mode) {
                        Text("編集").tag(Mode.edit)
                        Text("プレビュー").tag(Mode.preview)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isInsertingMedia || mediaErrorMessage != nil {
                    mediaStatusBar
                }
            }
            .photosPicker(
                isPresented: $isMediaPickerPresented,
                selection: $mediaPickerItem,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: mediaPickerItem) { _, newItem in
                guard let newItem else { return }
                handlePickedMedia(newItem)
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            NoPasteTextViewRepresentable(
                text: $text,
                onTextChanged: onTextChanged,
                accessory: .formatting,
                onRequestMediaInsert: allowsMediaInsertion ? { isMediaPickerPresented = true } : nil,
                insertionController: allowsMediaInsertion ? inserter : nil
            )
            .padding(AppSpacing.sm)

            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(AppColor.placeholder)
                    .padding(.horizontal, AppSpacing.md + 2)
                    .padding(.vertical, AppSpacing.md)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        ScrollView {
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .paperSurface()
            .padding(AppSpacing.md)
        }
    }

    private var mediaStatusBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(.ultraThinMaterial)
    }

    private func handlePickedMedia(_ item: PhotosPickerItem) {
        Task { @MainActor in
            isInsertingMedia = true
            mediaErrorMessage = nil
            defer {
                isInsertingMedia = false
                mediaPickerItem = nil
            }
            do {
                let media = try await loadComposeMedia(
                    from: item,
                    store: store,
                    uploadService: uploadService,
                    contentID: contentID
                )
                inserter.insert(InlineMedia.snippet(for: media))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                mediaErrorMessage = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
}
