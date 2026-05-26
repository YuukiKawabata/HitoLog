import SwiftUI

struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let postID: String
    @State private var commentText = ""
    @State private var didSendComment = false
    @State private var editingPost: Post?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Group {
            if let post = store.post(for: postID), let author = store.user(for: post.userId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            HStack(alignment: .top, spacing: AppSpacing.md) {
                                NavigationLink(destination: ProfileView(userID: author.id)) {
                                    AvatarView(user: author, size: 48)
                                }
                                .buttonStyle(.plain)

                                NavigationLink(destination: ProfileView(userID: author.id)) {
                                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                        SectionKicker(text: "Original Note")
                                        Text(author.displayName)
                                            .font(AppFont.userName)
                                            .foregroundStyle(AppColor.textPrimary)
                                        Text("@\(author.handle)")
                                            .font(.subheadline)
                                            .foregroundStyle(AppColor.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                if post.userId == store.currentUser.id {
                                    Menu {
                                        Button {
                                            editingPost = post
                                        } label: {
                                            Label("編集", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            isShowingDeleteConfirmation = true
                                        } label: {
                                            Label("削除", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppColor.textSecondary)
                                            .frame(width: 32, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                }
                            }

                            Text(post.body)
                                .font(AppFont.title)
                                .lineSpacing(7)
                                .foregroundStyle(AppColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            HumanSignalStrip(
                                title: post.humanBadge.displayText,
                                detail: "\(post.inputDurationMs / 1000)秒かけて書かれた投稿です。",
                                systemImage: post.humanBadge.systemImage
                            )

                            InkDivider()

                            HStack(spacing: AppSpacing.sm) {
                                Button {
                                    store.toggleLike(for: post.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    PaperMetricTile(
                                        title: "いいね",
                                        value: "\(post.likeCount)",
                                        systemImage: store.likedPostIDs.contains(post.id) ? "heart.fill" : "heart",
                                        tint: store.likedPostIDs.contains(post.id) ? AppColor.stamp : AppColor.accent
                                    )
                                }
                                .buttonStyle(.plain)

                                PaperMetricTile(title: "コメント", value: "\(post.commentCount)", systemImage: "bubble.right")
                                PaperMetricTile(title: "入力", value: "\(post.inputDurationMs / 1000)秒", systemImage: "keyboard")
                            }
                        }
                        .padding(AppSpacing.md)
                        .paperSurface()

                        CommentComposer(
                            text: $commentText,
                            didSendComment: didSendComment,
                            onSend: {
                                sendComment(to: post.id)
                            }
                        )

                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            SectionKicker(text: "Comments", systemImage: "bubble.right")

                            let comments = store.comments(for: post.id)
                            if comments.isEmpty {
                                Text("まだコメントがありません。最初の一言を残しましょう。")
                                    .font(.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(comments) { comment in
                                    if let user = store.user(for: comment.userId) {
                                        CommentRow(
                                            comment: comment,
                                            author: user,
                                            authorDestination: AnyView(ProfileView(userID: user.id))
                                        )
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .paperSurface()
                    }
                    .padding(AppSpacing.md)
                }
                .background(PaperCanvas())
            } else {
                ContentUnavailableView("投稿が見つかりません", systemImage: "text.bubble")
            }
        }
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPost) { post in
            PostEditSheet(post: post)
                .environmentObject(store)
        }
        .confirmationDialog("投稿を削除しますか？", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                store.deletePost(postID: postID)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("削除した投稿はタイムラインに表示されなくなります。")
        }
    }

    private func sendComment(to postID: String) {
        store.addComment(body: commentText, to: postID)
        commentText = ""
        didSendComment = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                didSendComment = false
            }
        }
    }
}

private struct PostDetailMetric: View {
    let title: String
    let value: String
    let systemImage: String
    var isActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(isActive ? AppColor.accent : AppColor.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CommentComposer: View {
    @Binding var text: String
    let didSendComment: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                ZStack(alignment: .topLeading) {
                    NoPasteTextViewRepresentable(
                        text: $text,
                        onTextChanged: { _, _ in }
                    )
                    .frame(minHeight: 44, maxHeight: 112)
                    .padding(.horizontal, AppSpacing.sm)

                    if text.isEmpty {
                        Text("コメントを書く")
                            .font(.body)
                            .foregroundStyle(AppColor.placeholder)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, 12)
                    }
                }
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(AppColor.border, lineWidth: 0.5)
                }

                Button(action: onSend) {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 38, height: 38)
                        .foregroundStyle(AppColor.background)
                        .background(canSend ? AppColor.accent : AppColor.textTertiary, in: Circle())
                }
                .disabled(!canSend)
            }

            if didSendComment {
                Label("コメントを投稿しました", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.accent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .animation(.snappy, value: didSendComment)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct CommentRow: View {
    let comment: Comment
    let author: AppUser
    let authorDestination: AnyView?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            authorAvatar

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    authorName
                    Text("・")
                        .font(.caption)
                        .foregroundStyle(AppColor.textTertiary)
                    Text(DateFormatterUtil.relativeString(from: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(comment.body)
                    .font(.subheadline)
                    .lineSpacing(4)
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.sm)
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let authorDestination {
            NavigationLink(destination: authorDestination) {
                AvatarView(user: author, size: 34)
            }
            .buttonStyle(.plain)
        } else {
            AvatarView(user: author, size: 34)
        }
    }

    @ViewBuilder
    private var authorName: some View {
        let label = HStack(spacing: AppSpacing.xs) {
            Text(author.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("@\(author.handle)")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }

        if let authorDestination {
            NavigationLink(destination: authorDestination) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}
