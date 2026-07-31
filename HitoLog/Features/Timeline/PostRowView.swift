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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if post.shareType != .original {
                PostShareContextLabel(post: post, author: author)
            }

            HStack(alignment: .top, spacing: AppSpacing.sm) {
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

                        Button(role: .destructive, action: onReport) {
                            Label("通報", systemImage: "exclamationmark.bubble")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("その他の操作")
            }

            if !post.body.isEmpty {
                MarkdownBodyView(markdown: post.body)
            }

            if !post.mediaItems.isEmpty {
                PostMediaGridView(mediaItems: post.mediaItems)
            }

            if let sourcePost = store.sourcePost(for: post),
               let sourceAuthor = store.user(for: sourcePost.userId) {
                ReferencedPostCard(post: sourcePost, author: sourceAuthor)
            }

            if post.shareType != .repost {
                PostIntegrityLine(post: post)
            }

            HStack(spacing: AppSpacing.sm) {
                Button(action: onLike) {
                    PostActionView(
                        systemImage: isLiked ? "heart.fill" : "heart",
                        value: post.likeCount,
                        isActive: isLiked,
                        activeTint: AppColor.stamp,
                        label: "いいね"
                    )
                }
                .buttonStyle(ScaleButtonStyle())

                if let commentDestination {
                    NavigationLink(destination: commentDestination) {
                        PostActionView(systemImage: "bubble.right", value: post.commentCount, label: "コメント")
                    }
                    .buttonStyle(ScaleButtonStyle())
                } else {
                    PostActionView(systemImage: "bubble.right", value: post.commentCount, label: "コメント")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(AppSpacing.md)
        .paperSurface(shadow: false)
        .padding(.horizontal, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let authorDestination {
            NavigationLink(destination: authorDestination) {
                AvatarView(user: author, size: 36)
            }
            .buttonStyle(.plain)
        } else {
            AvatarView(user: author, size: 36)
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
            return L10n.format("%@さんがリポスト", author.displayName)
        case .quote:
            return L10n.format("%@さんが引用", author.displayName)
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

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
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
                    Text(MarkdownInline.attributed(post.body))
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
                    SectionKicker(text: "引用".localized, systemImage: "quote.bubble")

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

struct TopicChip: View {
    let topic: String

    var body: some View {
        Text("#\(topic)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.accent)
            .lineLimit(1)
            .padding(.vertical, AppSpacing.xs)
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

private struct PostIntegrityLine: View {
    let post: Post

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Group {
                Image(systemName: post.humanBadge.systemImage)
                    .font(.caption2.weight(.semibold))
                Text(post.humanBadge.displayText)
            }
            .foregroundStyle(post.humanBadge == .verified ? AppColor.accent : AppColor.textSecondary)

            if post.aiAssisted {
                Text("・")
                    .foregroundStyle(AppColor.textTertiary)
                Text("AI併用")
                    .foregroundStyle(AppColor.inkBlue)
            }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
    }
}

private struct PostActionView: View {
    let systemImage: String
    let value: Int?
    var isActive = false
    var activeTint: Color = AppColor.stamp
    var label: String

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.callout)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isActive)
            if let value, value > 0 {
                Text("\(value)")
                    .font(.caption.weight(.semibold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
        }
        .foregroundStyle(isActive ? activeTint : AppColor.textSecondary)
        .padding(.horizontal, AppSpacing.xxs)
        .frame(minHeight: 32)
        .frame(minWidth: 34)
        .contentShape(Rectangle())
        .animation(.snappy(duration: 0.28), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { L10n.format("%@ %lld件", label, Int64($0)) } ?? label)
        .accessibilityAddTraits(.isButton)
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

/// 投稿者が AI併用を正直に開示したことを示すラベル。
struct AIAssistedBadge: View {
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "sparkles")
                .font(.caption2.weight(.semibold))
            Text("AI併用")
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(AppColor.inkBlue)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColor.inkBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(AppColor.inkBlue.opacity(0.28), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI併用を開示した投稿")
    }
}

/// いいねとは別軸の「思慮深い反応」を選ぶリアクションバー。
struct ReactionBar: View {
    let counts: [String: Int]
    let selected: ReactionKind?
    let onTap: (ReactionKind) -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(ReactionKind.allCases) { kind in
                let count = counts[kind.rawValue] ?? 0
                let isSelected = selected == kind
                Button {
                    onTap(kind)
                } label: {
                    HStack(spacing: AppSpacing.xxs) {
                        Text(kind.emoji)
                            .font(.caption)
                        Text(kind.displayText)
                            .font(.caption2.weight(.medium))
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                    .foregroundStyle(isSelected ? AppColor.accent : AppColor.textSecondary)
                    .padding(.vertical, AppSpacing.xs)
                    .padding(.horizontal, AppSpacing.sm)
                    .background(
                        (isSelected ? AppColor.accentSoft : AppColor.surface),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(isSelected ? AppColor.accent.opacity(0.3) : AppColor.border, lineWidth: 0.5)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel(Text(count > 0 ? L10n.format("%@ %lld件", kind.displayText, Int64(count)) : kind.displayText))
            }
            Spacer(minLength: 0)
        }
    }
}

/// 投稿詳細用の「この投稿の書かれ方」カード。
/// 人間が時間をかけ、推敲して書いたという HitoLog 独自の価値を可視化する。
struct WritingTraceCard: View {
    let trace: WritingTrace

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionKicker(text: "この投稿の書かれ方".localized, systemImage: trace.depth.systemImage)

            Text(trace.depth.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)

            HStack(spacing: AppSpacing.sm) {
                WritingTraceTile(title: "綴った時間".localized, value: trace.durationText, systemImage: "timer")
                WritingTraceTile(title: "文字数".localized, value: L10n.format("%lld字", Int64(trace.characterCount)), systemImage: "character.cursor.ibeam")
                WritingTraceTile(
                    title: "推敲".localized,
                    value: trace.revisionCount > 0 ? L10n.format("%lld回", Int64(trace.revisionCount)) : "—",
                    systemImage: "pencil.and.outline"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.5)
        }
    }
}

private struct WritingTraceTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(AppColor.border.opacity(0.7), lineWidth: 0.5)
        }
    }
}
