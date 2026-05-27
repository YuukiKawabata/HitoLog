import SwiftUI

struct PostDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let postID: String
    @State private var commentText = ""
    @State private var didSendComment = false
    @State private var editingPost: Post?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingQuoteSheet = false

    var body: some View {
        Group {
            if let post = store.post(for: postID), let author = store.user(for: post.userId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            if post.shareType != .original {
                                Label(post.shareType == .repost ? "\(author.displayName)さんがリポスト" : "\(author.displayName)さんが引用", systemImage: post.shareType == .repost ? "arrow.2.squarepath" : "quote.bubble")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textSecondary)
                            }

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

                                Menu {
                                    if post.userId == store.currentUser.id {
                                        if post.shareType != .repost {
                                            Button {
                                                editingPost = post
                                            } label: {
                                                Label("編集", systemImage: "pencil")
                                            }
                                        }
                                        Button(role: .destructive) {
                                            isShowingDeleteConfirmation = true
                                        } label: {
                                            Label("削除", systemImage: "trash")
                                        }
                                    } else {
                                        if store.mutedUserIDs.contains(author.id) {
                                            Button {
                                                store.unmute(author.id)
                                            } label: {
                                                Label("ミュート解除", systemImage: "speaker.wave.2")
                                            }
                                        } else {
                                            Button {
                                                store.mute(author.id)
                                            } label: {
                                                Label("ミュート", systemImage: "speaker.slash")
                                            }
                                        }

                                        if store.blockedUserIDs.contains(author.id) {
                                            Button {
                                                store.unblock(author.id)
                                            } label: {
                                                Label("ブロック解除", systemImage: "hand.raised.slash")
                                            }
                                        } else {
                                            Button(role: .destructive) {
                                                store.block(author.id)
                                            } label: {
                                                Label("ブロック", systemImage: "hand.raised")
                                            }
                                        }

                                        Button(role: .destructive) {
                                            store.addReport(
                                                targetType: .post,
                                                targetID: post.id,
                                                targetOwnerID: post.userId,
                                                targetDescription: "投稿: \(post.body.prefix(40))",
                                                reason: "不適切な投稿"
                                            )
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Label("通報", systemImage: "exclamationmark.bubble")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColor.textSecondary)
                                        .frame(width: 32, height: 28)
                                        .contentShape(Rectangle())
                                }
                            }

                            if !post.body.isEmpty {
                                Text(post.body)
                                    .font(AppFont.postDetailBody)
                                    .lineSpacing(5)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !post.mediaItems.isEmpty {
                                PostMediaGridView(mediaItems: post.mediaItems, isDetail: true)
                            }

                            if !post.topics.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: AppSpacing.xs) {
                                        ForEach(post.topics, id: \.self) { topic in
                                            DetailTopicChip(topic: topic)
                                        }
                                    }
                                }
                            }

                            if let sourcePost = store.sourcePost(for: post),
                               let sourceAuthor = store.user(for: sourcePost.userId) {
                                ReferencedPostCard(post: sourcePost, author: sourceAuthor)
                            }

                            if post.shareType != .repost {
                                HumanSignalStrip(
                                    title: post.humanBadge.displayText,
                                    detail: "\(post.inputDurationMs / 1000)秒かけて書かれた投稿です。",
                                    systemImage: post.humanBadge.systemImage
                                )
                            }

                            InkDivider()

                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: AppSpacing.sm),
                                    GridItem(.flexible(), spacing: AppSpacing.sm)
                                ],
                                spacing: AppSpacing.sm
                            ) {
                                let targetPost = store.shareTargetPost(for: post)
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

                                Button {
                                    store.toggleRepost(for: targetPost.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    PaperMetricTile(
                                        title: "リポスト",
                                        value: "\(targetPost.repostCount)",
                                        systemImage: "arrow.2.squarepath",
                                        tint: store.isReposted(targetPost.id) ? AppColor.stamp : AppColor.accent
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    isShowingQuoteSheet = true
                                } label: {
                                    PaperMetricTile(
                                        title: "引用",
                                        value: "\(targetPost.quoteCount)",
                                        systemImage: "quote.bubble"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    store.toggleBookmark(for: post.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    PaperMetricTile(
                                        title: "保存",
                                        value: store.isBookmarked(post.id) ? "済み" : "未保存",
                                        systemImage: store.isBookmarked(post.id) ? "bookmark.fill" : "bookmark",
                                        tint: store.isBookmarked(post.id) ? AppColor.stamp : AppColor.accent
                                    )
                                }
                                .buttonStyle(.plain)
                                PaperMetricTile(title: "入力", value: "\(post.inputDurationMs / 1000)秒", systemImage: "keyboard")
                            }
                        }
                        .padding(AppSpacing.md)
                        .paperSurface()

                        let permissionState = store.commentPermissionStatus(for: post)
                        if permissionState.canComment {
                            CommentComposer(
                                text: $commentText,
                                didSendComment: didSendComment,
                                isDisabled: store.currentUser.isSuspended,
                                onSend: {
                                    sendComment(to: post.id)
                                }
                            )
                        } else if let message = permissionState.message {
                            CommentPermissionNotice(message: message, permission: post.commentPermission)
                        }

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
                                            authorDestination: AnyView(ProfileView(userID: user.id)),
                                            canDelete: comment.userId == store.currentUser.id,
                                            canHide: post.userId == store.currentUser.id && comment.userId != store.currentUser.id,
                                            onDelete: {
                                                store.deleteComment(commentID: comment.id)
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            },
                                            onHide: {
                                                store.hideComment(commentID: comment.id)
                                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            },
                                            onReport: {
                                                store.addReport(
                                                    targetType: .comment,
                                                    targetID: comment.id,
                                                    targetOwnerID: comment.userId,
                                                    targetDescription: "コメント: \(comment.body.prefix(40))",
                                                    reason: "不適切なコメント"
                                                )
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            }
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
        .task(id: postID) {
            await store.loadComments(for: postID)
        }
        .sheet(item: $editingPost) { post in
            PostEditSheet(post: post)
                .environmentObject(store)
        }
        .sheet(isPresented: $isShowingQuoteSheet) {
            if let post = store.post(for: postID) {
                let targetPost = store.shareTargetPost(for: post)
                if let targetAuthor = store.user(for: targetPost.userId) {
                    QuotePostSheet(sourcePost: targetPost, sourceAuthor: targetAuthor)
                        .environmentObject(store)
                }
            }
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

private struct DetailTopicChip: View {
    let topic: String

    var body: some View {
        Text("#\(topic)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.accent)
            .padding(.vertical, 5)
            .padding(.horizontal, AppSpacing.sm)
            .background(AppColor.accent.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppColor.accent.opacity(0.18), lineWidth: 0.7)
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

private struct CommentPermissionNotice: View {
    let message: String
    let permission: CommentPermission

    var body: some View {
        Label(message, systemImage: permission.systemImage)
            .font(.subheadline)
            .foregroundStyle(AppColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .paperSurface()
    }
}

private struct CommentComposer: View {
    @Binding var text: String
    let didSendComment: Bool
    var isDisabled = false
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
            } else if isDisabled {
                Label("このアカウントは現在コメントできません。", systemImage: "person.crop.circle.badge.xmark")
                    .font(.caption)
                    .foregroundStyle(AppColor.warning)
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .animation(.snappy, value: didSendComment)
    }

    private var canSend: Bool {
        !isDisabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct CommentRow: View {
    let comment: Comment
    let author: AppUser
    let authorDestination: AnyView?
    var canDelete = false
    var canHide = false
    var onDelete: () -> Void = {}
    var onHide: () -> Void = {}
    var onReport: () -> Void = {}

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

            Menu {
                if canHide {
                    Button(role: .destructive, action: onHide) {
                        Label("非表示", systemImage: "eye.slash")
                    }
                }

                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("削除", systemImage: "trash")
                    }
                }

                if !canDelete {
                    Button(role: .destructive, action: onReport) {
                        Label("通報", systemImage: "exclamationmark.bubble")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 28, height: 28)
            }
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
