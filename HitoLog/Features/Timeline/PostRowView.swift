import SwiftUI
import UIKit

struct PostRowView: View {
    let post: Post
    let author: AppUser
    var isLiked = false
    var onLike: () -> Void = {}
    var commentDestination: AnyView? = nil
    var authorDestination: AnyView? = nil
    var showsOwnerActions = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                authorAvatar

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                        authorName

                        Text("・")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textTertiary)

                        Text(DateFormatterUtil.relativeString(from: post.createdAt))
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)

                        Spacer(minLength: AppSpacing.xs)

                        if showsOwnerActions {
                            Menu {
                                Button(action: onEdit) {
                                    Label("編集", systemImage: "pencil")
                                }
                                Button(role: .destructive, action: onDelete) {
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
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: AppSpacing.sm) {
                        HumanBadgeView(badge: post.humanBadge)
                        Text("\(post.inputDurationMs / 1000)秒で入力")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(spacing: AppSpacing.lg) {
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

                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.md + 2)
        .background(AppColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.border)
                .frame(height: 0.5)
                .padding(.leading, 68)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)

            Text("@\(author.handle)")
                .font(.subheadline)
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
                    .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .stroke(AppColor.border, lineWidth: 0.5)
                    }

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
            .background(AppColor.groupedBackground)
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
                .font(.subheadline)
            if let value {
                Text("\(value)")
                    .font(.subheadline)
            }
        }
        .foregroundStyle(isActive ? AppColor.accent : AppColor.textSecondary)
        .frame(minWidth: 44, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
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
                        colors: [AppColor.accent.opacity(0.24), AppColor.accent.opacity(0.08)],
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
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(AppColor.border, lineWidth: 0.5)
        }
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
        .background((badge == .verified ? AppColor.accent.opacity(0.12) : AppColor.surface), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
