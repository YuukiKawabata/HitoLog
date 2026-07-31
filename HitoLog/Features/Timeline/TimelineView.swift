import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var editingPost: Post?
    @State private var deletingPost: Post?
    var onComposeTap: () -> Void = {}

    var body: some View {
        let posts = visiblePosts

        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                TimelineHeaderView()
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)

                DailyPromptCard(onComposeTap: onComposeTap)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.sm)

                if posts.isEmpty {
                    EmptyTimelineView(
                        title: "まだ言葉がありません",
                        message: "今日のことをひとつ書くと、ここから記録が始まります。"
                    )
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.xl)
                } else {
                    ForEach(posts) { post in
                        if let author = store.user(for: post.userId) {
                            PostRowView(
                                post: post,
                                author: author,
                                isLiked: store.likedPostIDs.contains(post.id),
                                onLike: {
                                    store.toggleLike(for: post.id)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                commentDestination: AnyView(PostDetailView(postID: post.id)),
                                authorDestination: AnyView(ProfileView(userID: author.id)),
                                showsOwnerActions: post.userId == store.currentUser.id,
                                onEdit: { editingPost = post },
                                onDelete: { deletingPost = post },
                                onReport: {
                                    store.addReport(
                                        targetType: .post,
                                        targetID: post.id,
                                        targetOwnerID: post.userId,
                                        targetDescription: L10n.format("投稿: %@", String(post.body.prefix(40))),
                                        reason: "不適切な投稿"
                                    )
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            )
                        }
                    }

                    if store.isRemoteSyncEnabled && store.hasMoreTimelinePosts {
                        Button {
                            Task {
                                await store.loadMoreTimelinePosts()
                            }
                        } label: {
                            if store.isLoadingTimelinePage {
                                HStack(spacing: AppSpacing.sm) {
                                    ProgressView()
                                    Text("読み込み中")
                                }
                            } else {
                                Label("さらに読み込む", systemImage: "arrow.down.circle")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(store.isLoadingTimelinePage)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                    }
                }
            }
            .padding(.bottom, AppSpacing.lg)
        }
        .background(PaperCanvas())
        .refreshable {
            await store.refresh()
        }
        .navigationTitle("HitoLog")
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

    private var visiblePosts: [Post] {
        store.timelineItems.compactMap { item in
            guard case .post(let post) = item, post.shareType == .original else { return nil }
            return post
        }
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case following
    case recommended
    case rooms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "すべて".localized
        case .following:
            return "フォロー中".localized
        case .recommended:
            return "おすすめ".localized
        case .rooms:
            return "ルーム".localized
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "まだ表示できる投稿がありません".localized
        case .following:
            return "フォロー中の投稿はまだありません".localized
        case .recommended:
            return "おすすめできる投稿はまだありません".localized
        case .rooms:
            return "フォロー中ルームの投稿はまだありません".localized
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "他の人の投稿が届くと、ここに表示されます。".localized
        case .following:
            return "気になる人をフォローすると、ここに投稿が表示されます。".localized
        case .recommended:
            return "反応や本人入力率の高い投稿が見つかると、ここに表示されます。".localized
        case .rooms:
            return "気になる小部屋をフォローすると、ここに投稿が表示されます。".localized
        }
    }
}

private struct TimelineHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("今日の言葉")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("1日1つ、自分の言葉を残す。")
                .font(.caption)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DailyPromptCard: View {
    let onComposeTap: () -> Void

    var body: some View {
        Button(action: onComposeTap) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "pencil")
                    .font(.headline)
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 38, height: 38)
                    .background(AppColor.accentSoft, in: Circle())

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("今日のお題")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                    Text(DailyPrompt.current)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColor.border.opacity(0.6), lineWidth: 0.5)
            }
        }
        .buttonStyle(ScaleButtonStyle(scale: 0.98))
        .accessibilityHint("投稿画面を開きます")
    }
}

private struct TimelineStarterPackEmptyView: View {
    @EnvironmentObject private var store: AppDataStore
    let title: String
    let message: String
    @Binding var selectedCategory: StarterPackCategory

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            EmptyTimelineView(title: title, message: message)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionKicker(text: "スターターパック".localized, systemImage: selectedCategory.systemImage)

                Picker("スターターパック", selection: $selectedCategory) {
                    ForEach(StarterPackCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                let users = store.starterPackUsers(for: selectedCategory)
                if users.isEmpty {
                    Text("候補ユーザーはまだありません。")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(users) { user in
                        StarterPackUserRow(user: user)
                    }
                }
            }
            .padding(AppSpacing.md)
            .paperSurface()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, 64)
    }
}

private struct TimelineTopicRoomEmptyView: View {
    @EnvironmentObject private var store: AppDataStore
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            EmptyTimelineView(title: title, message: message)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionKicker(text: "ルーム".localized, systemImage: "number.square")

                let rooms = Array(store.discoverTopicRooms.prefix(6))
                if rooms.isEmpty {
                    Text("候補ルームはまだありません。")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(rooms) { room in
                        TopicRoomCompactRow(room: room)
                    }
                }
            }
            .padding(AppSpacing.md)
            .paperSurface()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, 64)
    }
}

private struct TopicRoomCompactRow: View {
    @EnvironmentObject private var store: AppDataStore
    let room: TopicRoom

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: TopicRoomView(topic: room.topic)) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: room.isOfficial ? "number.square.fill" : "number")
                        .font(.headline)
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(room.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(L10n.format("%lld件の投稿", Int64(room.postCount)))
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            FollowPillButton(isFollowing: store.isFollowingTopic(room.topic)) {
                store.toggleTopicFollow(topic: room.topic)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

private struct StarterPackUserRow: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: ProfileView(userID: user.id)) {
                HStack(spacing: AppSpacing.sm) {
                    AvatarView(user: user, size: 38)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
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

            Spacer()

            FollowPillButton(isFollowing: store.isFollowing(user.id)) {
                store.toggleFollow(userID: user.id)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

private struct EmptyTimelineView: View {
    var title = "まだ投稿がありません".localized
    var message = "あなたの言葉で、最初の投稿をしてみましょう。".localized

    @State private var appeared = false

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppColor.accent)
                .frame(width: 76, height: 76)
                .background(AppColor.accentSoft, in: Circle())
                .overlay {
                    Circle()
                        .stroke(AppColor.accent.opacity(0.18), lineWidth: 1)
                }
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppColor.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(appeared ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .paperSurface()
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }
}
