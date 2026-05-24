import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: AppDataStore
    let userID: String?
    @State private var editingPost: Post?
    @State private var deletingPost: Post?

    init(userID: String? = nil) {
        self.userID = userID
    }

    var body: some View {
        Group {
            if let user = displayedUser {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ProfileHeaderView(
                            user: user,
                            postCount: store.postCount(for: user.id)
                        )
                        .padding(AppSpacing.md)

                        Text("投稿")
                            .font(.headline)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, AppSpacing.sm)
                            .padding(.bottom, AppSpacing.xs)

                        let posts = profilePosts(for: user)
                        if posts.isEmpty {
                            ContentUnavailableView("投稿がありません", systemImage: "text.bubble")
                                .padding(.top, AppSpacing.xl)
                        } else {
                            ForEach(posts) { post in
                                PostRowView(
                                    post: post,
                                    author: user,
                                    isLiked: store.likedPostIDs.contains(post.id),
                                    onLike: {
                                        store.toggleLike(for: post.id)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    },
                                    commentDestination: AnyView(PostDetailView(postID: post.id)),
                                    authorDestination: AnyView(ProfileView(userID: user.id)),
                                    showsOwnerActions: post.userId == store.currentUser.id,
                                    onEdit: {
                                        editingPost = post
                                    },
                                    onDelete: {
                                        deletingPost = post
                                    }
                                )
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("ユーザーが見つかりません", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .background(AppColor.groupedBackground)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPost) { post in
            PostEditSheet(post: post)
                .environmentObject(store)
        }
        .confirmationDialog(
            "投稿を削除しますか？",
            isPresented: Binding(
                get: { deletingPost != nil },
                set: { isPresented in
                    if !isPresented {
                        deletingPost = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let deletingPost {
                    store.deletePost(postID: deletingPost.id)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                deletingPost = nil
            }
            Button("キャンセル", role: .cancel) {
                deletingPost = nil
            }
        } message: {
            Text("削除した投稿はタイムラインに表示されなくなります。")
        }
    }

    private var displayedUser: AppUser? {
        if let userID {
            return store.user(for: userID)
        }
        return store.currentUser
    }

    private var navigationTitle: String {
        guard let displayedUser, displayedUser.id != store.currentUser.id else {
            return "プロフィール"
        }
        return displayedUser.displayName
    }

    private func profilePosts(for user: AppUser) -> [Post] {
        store.posts
            .filter { $0.userId == user.id && !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct ProfileHeaderView: View {
    let user: AppUser
    let postCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                AvatarView(user: user, size: 76)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(user.displayName)
                        .font(.title2.weight(.bold))
                    Text("@\(user.handle)")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                    HumanBadgeView(badge: .verified)
                        .padding(.top, AppSpacing.xs)
                }

                Spacer()
            }

            Text(user.bio)
                .font(.body)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.sm) {
                ProfileCount(title: "投稿", value: "\(postCount)")
                ProfileCount(title: "フォロー", value: "52")
                ProfileCount(title: "フォロワー", value: "210")
            }

            HStack(spacing: AppSpacing.sm) {
                ProfileSignalTile(
                    title: "本人入力投稿率",
                    value: user.humanVerifiedPostRate.formatted(.percent.precision(.fractionLength(0))),
                    systemImage: "checkmark.seal"
                )
                ProfileSignalTile(
                    title: "Human Level",
                    value: "\(user.humanLevel)",
                    systemImage: "chart.bar.fill"
                )
            }
        }
        .padding(AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

private struct ProfileCount: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(value)
                .font(.headline)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileSignalTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
