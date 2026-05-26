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
        VStack(alignment: .leading, spacing: AppSpacing.md) {
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
                .font(AppFont.body)
                .lineSpacing(6)
                .foregroundStyle(AppColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.sm) {
                HumanBadgeView(badge: post.humanBadge)

                Label("\(post.inputDurationMs / 1000)秒", systemImage: "keyboard")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.textSecondary)

                Spacer(minLength: 0)
            }

            InkDivider()

            HStack(spacing: AppSpacing.sm) {
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
