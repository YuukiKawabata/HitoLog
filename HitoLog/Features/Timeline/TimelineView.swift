import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var editingPost: Post?
    @State private var deletingPost: Post?
    @State private var selectedFilter: TimelineFilter = .all
    @State private var selectedStarterPack: StarterPackCategory = .writers

    var body: some View {
        let items = itemsForSelectedFilter

        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                TimelineHeaderView()
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xs)

                Picker("タイムライン", selection: $selectedFilter) {
                    ForEach(TimelineFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.xs)

                if items.isEmpty {
                    if selectedFilter == .rooms {
                        TimelineTopicRoomEmptyView(
                            title: selectedFilter.emptyTitle,
                            message: selectedFilter.emptyMessage
                        )
                    } else if selectedFilter == .following || selectedFilter == .recommended {
                        TimelineStarterPackEmptyView(
                            title: selectedFilter.emptyTitle,
                            message: selectedFilter.emptyMessage,
                            selectedCategory: $selectedStarterPack
                        )
                    } else {
                        EmptyTimelineView(
                            title: selectedFilter.emptyTitle,
                            message: selectedFilter.emptyMessage
                        )
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, 96)
                    }
                } else {
                    ForEach(items) { item in
                        switch item {
                        case .post(let post):
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
                                    showsOwnerActions: post.userId == store.currentUser.id,
                                    onEdit: { editingPost = post },
                                    onDelete: { deletingPost = post },
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
                        case .article(let article):
                            if let author = store.user(for: article.userID) {
                                ArticleCardView(
                                    article: article,
                                    author: author,
                                    showsOwnerActions: article.userID == store.currentUser.id,
                                    onReport: {
                                        store.addReport(
                                            targetType: .article,
                                            targetID: article.id,
                                            targetOwnerID: article.userID,
                                            targetDescription: "記事: \(article.title.prefix(40))",
                                            reason: "不適切な記事"
                                        )
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                )
                            }
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
        .onChange(of: selectedFilter) { _, newValue in
            guard newValue == .recommended, store.isRemoteSyncEnabled, store.hasMoreTimelinePosts else { return }
            Task {
                await store.loadMoreTimelinePosts()
            }
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

    private var itemsForSelectedFilter: [TimelineItem] {
        switch selectedFilter {
        case .all:
            return store.timelineItems
        case .following:
            let followingIDs = store.followingUserIDs
            return store.timelineItems.filter { followingIDs.contains($0.userID) }
        case .recommended:
            return store.recommendedTimelinePosts.map { .post($0) }
        case .rooms:
            let followedTopics = store.followedTopicIDs
            return store.timelineItems.filter { !Set($0.topics).intersection(followedTopics).isEmpty }
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
            return "すべて"
        case .following:
            return "フォロー中"
        case .recommended:
            return "おすすめ"
        case .rooms:
            return "ルーム"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "まだ表示できる投稿がありません"
        case .following:
            return "フォロー中の投稿はまだありません"
        case .recommended:
            return "おすすめできる投稿はまだありません"
        case .rooms:
            return "フォロー中ルームの投稿はまだありません"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "他の人の投稿が届くと、ここに表示されます。"
        case .following:
            return "気になる人をフォローすると、ここに投稿が表示されます。"
        case .recommended:
            return "反応や本人入力率の高い投稿が見つかると、ここに表示されます。"
        case .rooms:
            return "気になる小部屋をフォローすると、ここに投稿が表示されます。"
        }
    }
}

private struct TimelineHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .center, spacing: AppSpacing.md) {
                BrandIconView(size: 44, showsShadow: false)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    SectionKicker(text: "Human Timeline", systemImage: "pencil.and.outline")
                    Text("いま書かれた言葉")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Spacer(minLength: 0)
            }

            Text("書いた時間の温度が、そのまま残るタイムライン。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            InkDivider()
        }
        .padding(AppSpacing.md)
        .paperSurface()
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
                SectionKicker(text: "Starter Pack", systemImage: selectedCategory.systemImage)

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
                SectionKicker(text: "Topic Rooms", systemImage: "number.square")

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(room.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text("\(room.postCount)件の投稿")
                            .font(.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.toggleTopicFollow(topic: room.topic)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(store.isFollowingTopic(room.topic) ? "フォロー中" : "フォロー", systemImage: store.isFollowingTopic(room.topic) ? "checkmark" : "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
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

            Spacer()

            Button {
                store.toggleFollow(userID: user.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label(store.isFollowing(user.id) ? "フォロー中" : "フォロー", systemImage: store.isFollowing(user.id) ? "checkmark" : "plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

private struct EmptyTimelineView: View {
    var title = "まだ投稿がありません"
    var message = "あなたの言葉で、最初の投稿をしてみましょう。"

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accent)

            Text(title)
                .font(AppFont.sectionTitle)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .paperSurface()
    }
}
