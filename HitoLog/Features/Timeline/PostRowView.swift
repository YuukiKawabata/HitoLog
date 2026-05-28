import SwiftUI
import UIKit

struct PostRowView: View {
    @EnvironmentObject private var store: AppDataStore
    let post: Post
    let author: AppUser
    var isLiked = false
    var isBookmarked = false
    var onLike: () -> Void = {}
    var onBookmark: () -> Void = {}
    var commentDestination: AnyView? = nil
    var authorDestination: AnyView? = nil
    var showsOwnerActions = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onReport: () -> Void = {}
    @State private var isShowingQuoteSheet = false
    @State private var isShowingRecommendationReason = false
    @State private var recommendationReason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if post.shareType != .original {
                PostShareContextLabel(post: post, author: author)
            }

            HStack(alignment: .top, spacing: AppSpacing.md) {
                authorAvatar

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                        authorName

                        Spacer(minLength: AppSpacing.xs)

                        Text(DateFormatterUtil.relativeString(from: post.createdAt))
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                Menu {
                    if showsOwnerActions {
                        if post.shareType != .repost {
                            Button(action: onEdit) {
                                Label("編集", systemImage: "pencil")
                            }
                        }
                        Button(role: .destructive, action: onDelete) {
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

                        if !post.topics.isEmpty {
                            Menu {
                                ForEach(post.topics, id: \.self) { topic in
                                    Button("#\(topic)") {
                                        store.setFeedControl(topic: topic, preference: .boost)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                }
                            } label: {
                                Label("このルームを増やす", systemImage: "arrow.up.circle")
                            }

                            Menu {
                                ForEach(post.topics, id: \.self) { topic in
                                    Button("#\(topic)") {
                                        store.setFeedControl(topic: topic, preference: .reduce)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                }
                            } label: {
                                Label("この話題を減らす", systemImage: "arrow.down.circle")
                            }
                        }

                        Button {
                            recommendationReason = store.recommendationExplanation(for: post)
                            isShowingRecommendationReason = true
                        } label: {
                            Label("おすすめ理由", systemImage: "questionmark.circle")
                        }

                        Button(role: .destructive, action: onReport) {
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
                    .font(AppFont.postBody)
                    .lineSpacing(4)
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !post.mediaItems.isEmpty {
                PostMediaGridView(mediaItems: post.mediaItems)
            }

            if !post.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(post.topics, id: \.self) { topic in
                            TopicChip(topic: topic)
                        }
                    }
                }
            }

            if let sourcePost = store.sourcePost(for: post),
               let sourceAuthor = store.user(for: sourcePost.userId) {
                ReferencedPostCard(post: sourcePost, author: sourceAuthor)
            }

            if post.shareType != .repost {
                HStack(spacing: AppSpacing.sm) {
                    HumanBadgeView(badge: post.humanBadge)

                    Label("\(post.inputDurationMs / 1000)秒", systemImage: "keyboard")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColor.textSecondary)

                    Spacer(minLength: 0)
                }
            }

            InkDivider()

            HStack(spacing: AppSpacing.sm) {
                let targetPost = store.shareTargetPost(for: post)
                Button(action: onLike) {
                    PostActionView(
                        systemImage: isLiked ? "heart.fill" : "heart",
                        value: post.likeCount,
                        isActive: isLiked
                    )
                }
                .buttonStyle(.plain)

                if let commentDestination {
                    NavigationLink(destination: commentDestination) {
                        PostActionView(systemImage: "bubble.right", value: post.commentCount)
                    }
                    .buttonStyle(.plain)
                } else {
                    PostActionView(systemImage: "bubble.right", value: post.commentCount)
                }

                Button {
                    store.toggleRepost(for: targetPost.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    PostActionView(
                        systemImage: "arrow.2.squarepath",
                        value: targetPost.repostCount,
                        isActive: store.isReposted(targetPost.id)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    isShowingQuoteSheet = true
                } label: {
                    PostActionView(systemImage: "quote.bubble", value: targetPost.quoteCount)
                }
                .buttonStyle(.plain)

                Button(action: onBookmark) {
                    PostActionView(
                        systemImage: isBookmarked ? "bookmark.fill" : "bookmark",
                        value: nil,
                        isActive: isBookmarked
                    )
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppColor.accent.opacity(0.72))
                .frame(width: 2)
                .padding(.vertical, AppSpacing.md)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.xs)
        .sheet(isPresented: $isShowingQuoteSheet) {
            let targetPost = store.shareTargetPost(for: post)
            if let targetAuthor = store.user(for: targetPost.userId) {
                QuotePostSheet(sourcePost: targetPost, sourceAuthor: targetAuthor)
                    .environmentObject(store)
            }
        }
        .alert("おすすめ理由", isPresented: $isShowingRecommendationReason) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recommendationReason)
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let authorDestination {
            NavigationLink(destination: authorDestination) {
                AvatarView(user: author, size: 42)
            }
            .buttonStyle(.plain)
        } else {
            AvatarView(user: author, size: 42)
        }
    }

    @ViewBuilder
    private var authorName: some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(author.displayName)
                .font(AppFont.userName)
                .foregroundStyle(AppColor.textPrimary)

            Text("@\(author.handle)")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
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

private struct PostShareContextLabel: View {
    let post: Post
    let author: AppUser

    var body: some View {
        Label(contextText, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.textSecondary)
            .lineLimit(1)
    }

    private var contextText: String {
        switch post.shareType {
        case .repost:
            return "\(author.displayName)さんがリポスト"
        case .quote:
            return "\(author.displayName)さんが引用"
        case .original:
            return ""
        }
    }

    private var systemImage: String {
        switch post.shareType {
        case .repost:
            return "arrow.2.squarepath"
        case .quote:
            return "quote.bubble"
        case .original:
            return "text.bubble"
        }
    }
}

struct ReferencedPostCard: View {
    let post: Post
    let author: AppUser

    var body: some View {
        NavigationLink(destination: PostDetailView(postID: post.id)) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    AvatarView(user: author, size: 28)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(author.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Text("@\(author.handle)")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                if !post.body.isEmpty {
                    Text(post.body)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let mediaItem = post.mediaItems.first {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: mediaItem.type == .video ? "play.rectangle" : "photo")
                        Text(mediaItem.type == .video ? "動画付き投稿" : "画像付き投稿")
                    }
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

struct QuotePostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let sourcePost: Post
    let sourceAuthor: AppUser
    @State private var text = ""
    @State private var metrics = TypingMetrics()
    @State private var isShowingValidationError = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    SectionKicker(text: "Quote", systemImage: "quote.bubble")

                    ZStack(alignment: .topLeading) {
                        NoPasteTextViewRepresentable(
                            text: $text,
                            onTextChanged: { oldText, newText in
                                metrics.recordChange(from: oldText, to: newText, at: Date())
                            }
                        )
                        .frame(minHeight: 180)
                        .padding(AppSpacing.sm)

                        if text.isEmpty {
                            Text("引用コメントを書く")
                                .font(.body)
                                .foregroundStyle(AppColor.placeholder)
                                .padding(.horizontal, AppSpacing.md + 4)
                                .padding(.vertical, AppSpacing.md + 2)
                        }
                    }
                    .paperSurface(shadow: false)

                    HStack {
                        Label("ペースト不可", systemImage: "doc.on.clipboard")
                        Spacer()
                        Text("\(text.count)/\(AppConstants.maxPostLength)")
                            .foregroundStyle(isNearLimit ? AppColor.warning : AppColor.textSecondary)
                    }
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)

                    ReferencedPostCard(post: sourcePost, author: sourceAuthor)
                }
                .padding(AppSpacing.md)
            }
            .background(PaperCanvas())
            .navigationTitle("引用投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
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
            .alert("投稿できません", isPresented: $isShowingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("引用コメントを入力してください。")
            }
            .onReceive(timer) { _ in
                metrics.refreshDuration(at: Date())
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !store.currentUser.isSuspended
            && !trimmedText.isEmpty
            && trimmedText.count <= AppConstants.maxPostLength
    }

    private var isNearLimit: Bool {
        AppConstants.maxPostLength - text.count <= 40
    }

    private func submit() {
        guard canSubmit else {
            isShowingValidationError = true
            return
        }

        store.quotePost(sourcePostID: sourcePost.id, body: trimmedText, metrics: metrics)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

private struct TopicChip: View {
    let topic: String

    var body: some View {
        Text("#\(topic)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.accent)
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, AppSpacing.sm)
            .background(AppColor.accent.opacity(0.08), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AppColor.accent.opacity(0.18), lineWidth: 0.7)
            }
    }
}

struct PostEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppDataStore
    let post: Post
    @State private var text: String
    @State private var isShowingValidationError = false

    init(post: Post) {
        self.post = post
        _text = State(initialValue: post.body)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ZStack(alignment: .topLeading) {
                        NoPasteTextViewRepresentable(
                            text: $text,
                            onTextChanged: { _, _ in }
                        )
                        .frame(minHeight: 220)
                        .padding(AppSpacing.sm)

                        if text.isEmpty {
                            Text("投稿を編集")
                                .font(.body)
                                .foregroundStyle(AppColor.placeholder)
                                .padding(.horizontal, AppSpacing.md + 4)
                                .padding(.vertical, AppSpacing.md + 2)
                        }
                    }
                    .paperSurface(shadow: false)

                    VStack(spacing: AppSpacing.xs) {
                        ProgressView(
                            value: min(Double(text.count), Double(AppConstants.maxPostLength)),
                            total: Double(AppConstants.maxPostLength)
                        )
                        .tint(isNearLimit ? AppColor.warning : AppColor.accent)

                        HStack {
                            Label("ペースト不可", systemImage: "doc.on.clipboard")
                            Spacer()
                            Text("\(text.count)/\(AppConstants.maxPostLength)")
                                .foregroundStyle(isNearLimit ? AppColor.warning : AppColor.textSecondary)
                        }
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(PaperCanvas())
            .navigationTitle("投稿を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("保存できません", isPresented: $isShowingValidationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("投稿本文を入力してください。")
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedText.isEmpty && trimmedText.count <= AppConstants.maxPostLength && trimmedText != post.body
    }

    private var isNearLimit: Bool {
        AppConstants.maxPostLength - text.count <= 40
    }

    private func save() {
        guard canSave else {
            isShowingValidationError = true
            return
        }

        store.updatePost(postID: post.id, body: trimmedText)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

private struct PostActionView: View {
    let systemImage: String
    let value: Int?
    var isActive = false

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
            if let value {
                Text("\(value)")
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(isActive ? AppColor.stamp : AppColor.textSecondary)
        .padding(.horizontal, AppSpacing.sm)
        .frame(minWidth: 52, minHeight: 32, alignment: .center)
        .background((isActive ? AppColor.stamp.opacity(0.08) : AppColor.surface), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(isActive ? AppColor.stamp.opacity(0.22) : AppColor.border, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

struct AvatarView: View {
    let user: AppUser
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColor.accentSoft, AppColor.background],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let avatarImage = user.avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(user.initials)
                    .font(.system(size: size * 0.34, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColor.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(AppColor.border, lineWidth: 0.8)
        }
        .shadow(color: AppColor.shadow, radius: 6, y: 3)
    }
}

private extension AppUser {
    var avatarImage: UIImage? {
        guard let avatarUrl,
              avatarUrl.hasPrefix("data:image"),
              let base64 = avatarUrl.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(base64)) else {
            return nil
        }

        return UIImage(data: data)
    }
}

struct HumanBadgeView: View {
    let badge: HumanBadge

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: badge.systemImage)
                .font(.caption2.weight(.semibold))
            Text(badge.displayText)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(badge == .verified ? AppColor.accent : AppColor.textSecondary)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background((badge == .verified ? AppColor.accentSoft : AppColor.surface), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(badge == .verified ? AppColor.accent.opacity(0.28) : AppColor.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}
