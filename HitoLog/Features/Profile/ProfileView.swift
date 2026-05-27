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

                        SectionKicker(text: "Posts", systemImage: "text.bubble")
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.top, AppSpacing.sm)
                            .padding(.bottom, AppSpacing.sm)

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
                                    isBookmarked: store.isBookmarked(post.id),
                                    onLike: {
                                        store.toggleLike(for: post.id)
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    },
                                    onBookmark: {
                                        store.toggleBookmark(for: post.id)
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
                                    },
                                    onReport: {
                                        store.addReport(
                                            targetType: .post,
                                            targetID: post.id,
                                            targetOwnerID: post.userId,
                                            targetDescription: "投稿: \(post.body.prefix(40))",
                                            reason: "不適切な投稿"
                                        )
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        .background(PaperCanvas())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if displayedUser?.id == store.currentUser.id {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        BookmarkedPostsView()
                    } label: {
                        Image(systemName: "bookmark")
                    }

                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
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
            .filter {
                $0.userId == user.id
                && !$0.isDeleted
                && !store.blockedUserIDs.contains($0.userId)
                && !store.mutedUserIDs.contains($0.userId)
                && (store.currentUser.isAdmin || $0.moderationStatus == .active)
                && ($0.shareType == .original || store.sourcePost(for: $0) != nil)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct ProfileHeaderView: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser
    let postCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    AvatarView(user: user, size: 76)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        SectionKicker(text: "Profile")

                        Text(user.displayName)
                            .font(AppFont.title)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("@\(user.handle)")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                        HumanBadgeView(badge: .verified)
                            .padding(.top, AppSpacing.xs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if user.id != store.currentUser.id {
                        reportMenu
                    }
                }

                if user.id != store.currentUser.id && !store.blockedUserIDs.contains(user.id) {
                    followButton
                } else if store.blockedUserIDs.contains(user.id) {
                    Label("ブロック中", systemImage: "hand.raised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.warning)
                        .padding(.vertical, 8)
                        .padding(.horizontal, AppSpacing.sm)
                        .background(AppColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
            }

            Text(user.bio)
                .font(AppFont.body)
                .lineSpacing(5)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.sm) {
                ProfileCount(title: "投稿", value: "\(postCount)")

                NavigationLink {
                    FollowListView(user: user, mode: .following)
                } label: {
                    ProfileCount(title: "フォロー", value: "\(store.followingCount(for: user.id))")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    FollowListView(user: user, mode: .followers)
                } label: {
                    ProfileCount(title: "フォロワー", value: "\(store.followerCount(for: user.id))")
                }
                .buttonStyle(.plain)
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
        .paperSurface()
    }

    private var followButton: some View {
        let isFollowing = store.isFollowing(user.id)

        return Button {
            store.toggleFollow(userID: user.id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(isFollowing ? "フォロー中" : "フォロー", systemImage: isFollowing ? "checkmark" : "plus")
                .font(AppFont.button)
                .labelStyle(.titleAndIcon)
                .padding(.vertical, 9)
                .padding(.horizontal, AppSpacing.md)
                .frame(minWidth: 132)
                .foregroundStyle(isFollowing ? AppColor.textPrimary : AppColor.background)
                .background(
                    isFollowing ? AppColor.background : AppColor.accent,
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(isFollowing ? AppColor.border : AppColor.accent.opacity(0.3), lineWidth: 0.7)
                }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var reportMenu: some View {
        Menu {
            if store.mutedUserIDs.contains(user.id) {
                Button {
                    store.unmute(user.id)
                } label: {
                    Label("ミュート解除", systemImage: "speaker.wave.2")
                }
            } else {
                Button {
                    store.mute(user.id)
                } label: {
                    Label("ミュート", systemImage: "speaker.slash")
                }
            }

            if store.blockedUserIDs.contains(user.id) {
                Button {
                    store.unblock(user.id)
                } label: {
                    Label("ブロック解除", systemImage: "hand.raised.slash")
                }
            } else {
                Button(role: .destructive) {
                    store.block(user.id)
                } label: {
                    Label("ブロック", systemImage: "hand.raised")
                }
            }

            Button(role: .destructive) {
                store.addReport(
                    targetType: .user,
                    targetID: user.id,
                    targetOwnerID: user.id,
                    targetDescription: "ユーザー: @\(user.handle)",
                    reason: "不適切なユーザー"
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("通報", systemImage: "exclamationmark.bubble")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }
}

private struct ProfileCount: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(value)
                .font(.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.5)
        }
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
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.5)
        }
    }
}

private struct BookmarkedPostsView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                if store.bookmarkedPosts.isEmpty {
                    ContentUnavailableView("保存した投稿はまだありません", systemImage: "bookmark")
                        .padding(AppSpacing.xl)
                        .paperSurface()
                        .padding(AppSpacing.md)
                } else {
                    ForEach(store.bookmarkedPosts) { post in
                        if let author = store.user(for: post.userId) {
                            PostRowView(
                                post: post,
                                author: author,
                                isLiked: store.likedPostIDs.contains(post.id),
                                isBookmarked: store.isBookmarked(post.id),
                                onLike: {
                                    store.toggleLike(for: post.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onBookmark: {
                                    store.toggleBookmark(for: post.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                commentDestination: AnyView(PostDetailView(postID: post.id)),
                                authorDestination: AnyView(ProfileView(userID: author.id)),
                                onReport: {
                                    store.addReport(
                                        targetType: .post,
                                        targetID: post.id,
                                        targetOwnerID: post.userId,
                                        targetDescription: "投稿: \(post.body.prefix(40))",
                                        reason: "不適切な投稿"
                                    )
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(PaperCanvas())
        .navigationTitle("ブックマーク")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadBookmarkedPosts()
        }
        .refreshable {
            await store.loadBookmarkedPosts()
        }
    }
}

private enum FollowListMode {
    case following
    case followers

    var title: String {
        switch self {
        case .following:
            return "フォロー"
        case .followers:
            return "フォロワー"
        }
    }

    var emptyText: String {
        switch self {
        case .following:
            return "フォロー中のユーザーはいません"
        case .followers:
            return "フォロワーはまだいません"
        }
    }
}

private struct FollowListView: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser
    let mode: FollowListMode

    var body: some View {
        List {
            if displayedUsers.isEmpty {
                ContentUnavailableView(mode.emptyText, systemImage: "person.2")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(displayedUsers) { listedUser in
                    FollowUserRow(user: listedUser)
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadFollowLists(for: user.id)
        }
    }

    private var displayedUsers: [AppUser] {
        switch mode {
        case .following:
            return store.following(for: user.id)
        case .followers:
            return store.followers(for: user.id)
        }
    }
}

private struct FollowUserRow: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: ProfileView(userID: user.id)) {
                HStack(spacing: AppSpacing.md) {
                    AvatarView(user: user, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("@\(user.handle)")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: AppSpacing.sm)

            if user.id != store.currentUser.id {
                Button {
                    store.toggleFollow(userID: user.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(store.isFollowing(user.id) ? "フォロー中" : "フォロー")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 7)
                        .padding(.horizontal, AppSpacing.sm)
                        .foregroundStyle(store.isFollowing(user.id) ? AppColor.textPrimary : AppColor.background)
                        .background(
                            store.isFollowing(user.id) ? AppColor.surface : AppColor.accent,
                            in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .stroke(store.isFollowing(user.id) ? AppColor.border : AppColor.accent.opacity(0.3), lineWidth: 0.7)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
