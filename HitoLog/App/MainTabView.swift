import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var flags: FeatureFlagService

    var body: some View {
        if flags.enableCircles && flags.circlesAsDefaultHome {
            WamoriMainTabView()
        } else {
            LegacyMainTabView()
        }
    }
}

private struct LegacyMainTabView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var flags: FeatureFlagService
    @State private var selectedTab: MainTab = .home
    @State private var lastContentTab: MainTab = .home
    @State private var homeNavigationPath = NavigationPath()
    @State private var isShowingCompose = false
    @State private var isShowingPostToast = false
    @State private var celebrationToken = 0
    @State private var toastMessage = "投稿しました"
    @State private var toastSystemImage = "checkmark.circle.fill"
    @State private var toastShowsCelebration = true

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homeNavigationPath) {
                TimelineView {
                    showCompose(source: "daily_prompt")
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            homeNavigationPath.append(HomeDestination.search)
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("検索")

                        Button {
                            homeNavigationPath.append(HomeDestination.notifications)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")

                                if store.unreadNotificationCount > 0 {
                                    Circle()
                                        .fill(AppColor.stamp)
                                        .frame(width: 7, height: 7)
                                    .offset(x: 2, y: -2)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("通知")
                    }
                }
                .navigationDestination(for: HomeDestination.self) { destination in
                    switch destination {
                    case .search:
                        UserSearchView()
                    case .notifications:
                        NotificationsView()
                    }
                }
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }
            .tag(MainTab.home)

            if flags.enableCircles {
                CircleNavigationView()
                    .tabItem { Label("輪", systemImage: "circle.grid.2x2") }
                    .tag(MainTab.circles)
            }

            Color.clear
            .tabItem {
                Label("書く", systemImage: "square.and.pencil")
            }
            .tag(MainTab.compose)

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("プロフィール", systemImage: "person.crop.circle")
            }
            .tag(MainTab.profile)
        }
        .tint(AppColor.accent)
        .sheet(isPresented: $isShowingCompose) {
            ComposePostView {
                showCompletionToast(message: "投稿しました", systemImage: "checkmark.circle.fill", celebration: true)
            }
        }
        .overlay(alignment: .top) {
            if isShowingPostToast {
                PostSubmittedToast(message: toastMessage, systemImage: toastSystemImage)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isShowingPostToast && toastShowsCelebration {
                PostSubmittedCelebration(token: celebrationToken)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: isShowingPostToast)
        .onAppear {
            analytics.screen(selectedTab.analyticsName)
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .compose {
                showCompose(source: "tab")
                selectedTab = lastContentTab
            } else {
                lastContentTab = tab
                analytics.screen(tab.analyticsName)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenFutureReflection)) { _ in
            selectedTab = .profile
        }
    }

    private func showCompose(source: String) {
        analytics.capture("compose_opened", properties: ["source": source])
        isShowingCompose = true
    }

    private func showCompletionToast(message: String, systemImage: String, celebration: Bool) {
        toastMessage = message
        toastSystemImage = systemImage
        toastShowsCelebration = celebration
        celebrationToken += 1
        let currentToken = celebrationToken
        isShowingPostToast = true
        Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            await MainActor.run {
                if celebrationToken == currentToken {
                    isShowingPostToast = false
                }
            }
        }
    }
}

private enum HomeDestination: Hashable {
    case search
    case notifications
}

private enum MainTab: String {
    case home
    case circles
    case compose
    case profile

    var analyticsName: String {
        switch self {
        case .home:
            return "timeline"
        case .circles:
            return "circle_list"
        case .compose:
            return "compose"
        case .profile:
            return "profile"
        }
    }
}

private struct UserSearchView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var query = ""
    @State private var scope: SearchScope = .users
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            Picker("検索対象", selection: $scope) {
                ForEach(SearchScope.allCases) { scope in
                    Label(scope.title, systemImage: scope.systemImage).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if scope == .users && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("フォロー候補") {
                    if store.followSuggestions.isEmpty {
                        ContentUnavailableView("候補はまだありません", systemImage: "person.crop.circle.badge.plus")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.followSuggestions) { user in
                            UserSearchRow(user: user)
                        }
                    }
                }
            } else if scope == .users {
                Section("検索結果") {
                    if store.searchResults.isEmpty {
                        ContentUnavailableView("ユーザーが見つかりません", systemImage: "magnifyingglass")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.searchResults) { user in
                            UserSearchRow(user: user)
                        }
                    }
                }
            } else if scope == .rooms && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("フォロー中ルーム") {
                    let followedRooms = store.discoverTopicRooms.filter { store.isFollowingTopic($0.topic) }
                    if followedRooms.isEmpty {
                        ContentUnavailableView("フォロー中のルームはまだありません", systemImage: "number.square")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(followedRooms) { room in
                            TopicRoomSearchRow(room: room)
                        }
                    }
                }

                Section("おすすめルーム") {
                    let rooms = store.discoverTopicRooms.filter { !store.isFollowingTopic($0.topic) }
                    if rooms.isEmpty {
                        ContentUnavailableView("候補ルームはまだありません", systemImage: "number.square")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(rooms.prefix(12))) { room in
                            TopicRoomSearchRow(room: room)
                        }
                    }
                }
            } else if scope == .rooms {
                Section("ルーム検索") {
                    if store.topicRoomSearchResults.isEmpty {
                        ContentUnavailableView("ルームが見つかりません", systemImage: "number.square")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.topicRoomSearchResults) { room in
                            TopicRoomSearchRow(room: room)
                        }
                    }
                }
            } else if scope == .topics && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("話題") {
                    if store.trendingTopics.isEmpty {
                        ContentUnavailableView("話題はまだありません", systemImage: "number")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.trendingTopics) { trend in
                            TopicTrendRow(trend: trend) {
                                scope = .topics
                                query = trend.displayText
                                Task {
                                    await runSearch(for: trend.displayText, scope: .topics)
                                }
                            }
                        }
                    }
                }
            } else if scope == .topics {
                Section(topicSectionTitle) {
                    if store.topicSearchResults.isEmpty {
                        ContentUnavailableView("この話題の投稿はまだありません", systemImage: "number")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.topicSearchResults) { post in
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
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("投稿検索") {
                    ContentUnavailableView("キーワードで投稿を検索できます", systemImage: "text.magnifyingglass")
                        .listRowBackground(Color.clear)
                }
            } else {
                Section("投稿検索") {
                    if store.postSearchResults.isEmpty {
                        ContentUnavailableView("投稿が見つかりません", systemImage: "text.magnifyingglass")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.postSearchResults) { post in
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
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle("検索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: scope.prompt)
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue, scope: scope)
        }
        .onChange(of: scope) { _, newValue in
            scheduleSearch(for: query, scope: newValue)
        }
    }

    private var topicSectionTitle: String {
        if let topic = TopicExtractor.normalizedTopicQuery(from: query) {
            return "#\(topic)"
        }
        return "話題検索".localized
    }

    private func scheduleSearch(for value: String, scope: SearchScope) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(for: value, scope: scope)
        }
    }

    private func runSearch(for value: String, scope: SearchScope) async {
        switch scope {
        case .users:
            await store.searchUsers(query: value)
        case .topics:
            await store.searchTopicPosts(query: value)
        case .rooms:
            await store.searchTopicRooms(query: value)
        case .posts:
            await store.searchPosts(query: value)
        }
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case users
    case topics
    case rooms
    case posts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .users: return "ユーザー".localized
        case .topics: return "話題".localized
        case .rooms: return "ルーム".localized
        case .posts: return "投稿".localized
        }
    }

    var systemImage: String {
        switch self {
        case .users: return "person.2"
        case .topics: return "number"
        case .rooms: return "number.square"
        case .posts: return "text.magnifyingglass"
        }
    }

    var prompt: String {
        switch self {
        case .users: return "名前またはユーザー名".localized
        case .topics: return "#健康 など".localized
        case .rooms: return "ルーム名または#topic".localized
        case .posts: return "投稿本文を検索".localized
        }
    }
}

private struct TopicTrendRow: View {
    let trend: TopicTrend
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "number")
                    .font(.headline)
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(trend.displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(L10n.format("%lld件の投稿", Int64(trend.postCount)))
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
    }
}

private struct TopicRoomSearchRow: View {
    @EnvironmentObject private var store: AppDataStore
    let room: TopicRoom

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: TopicRoomView(topic: room.topic)) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: room.isOfficial ? "number.square.fill" : "number.square")
                        .font(.headline)
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(room.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(L10n.format("%lld件の投稿 ・ %lld人がフォロー", Int64(room.postCount), Int64(room.followerCount)))
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

struct TopicRoomView: View {
    @EnvironmentObject private var store: AppDataStore
    let topic: String
    @State private var sort: TopicRoomPostSort = .latest

    var body: some View {
        let room = store.topicRoom(for: topic)
        let posts = store.topicRoomPosts(for: topic, sort: sort)

        List {
            Section {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Image(systemName: room.isOfficial ? "number.square.fill" : "number.square")
                            .font(.title2)
                            .foregroundStyle(AppColor.accent)
                            .frame(width: 44, height: 44)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            SectionKicker(text: "ルーム".localized, systemImage: "person.3")
                            Text(room.displayTitle)
                                .font(AppFont.title)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(room.displayDescription)
                                .font(.subheadline)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Label("\(room.postCount)", systemImage: "text.bubble")
                        Label("\(room.followerCount)", systemImage: "person.2")
                        if let lastPostAt = room.lastPostAt {
                            Label(DateFormatterUtil.relativeString(from: lastPostAt), systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)

                    if store.isFollowingTopic(room.topic) {
                        Button {
                            store.toggleTopicFollow(topic: room.topic)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label("フォロー中", systemImage: "checkmark")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button {
                            store.toggleTopicFollow(topic: room.topic)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label("このルームをフォロー", systemImage: "plus")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    let activePreference = store.feedControl(for: room.topic)?.preference
                    HStack(spacing: AppSpacing.sm) {
                        Button {
                            store.setFeedControl(topic: room.topic, preference: .boost)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(activePreference == .boost ? "増やす中" : "増やす", systemImage: activePreference == .boost ? "arrow.up.circle.fill" : "arrow.up.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        Button {
                            store.setFeedControl(topic: room.topic, preference: .reduce)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label(activePreference == .reduce ? "減らす中" : "減らす", systemImage: activePreference == .reduce ? "arrow.down.circle.fill" : "arrow.down.circle")
                        }
                        .buttonStyle(SecondaryButtonStyle())

                        if activePreference != nil {
                            Button {
                                store.clearFeedControl(topic: room.topic)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppColor.textSecondary)
                            .accessibilityLabel("標準に戻す")
                        }
                    }
                }
                .padding(.vertical, AppSpacing.sm)
            }
            .listRowBackground(Color.clear)

            Section("投稿") {
                Picker("並び順", selection: $sort) {
                    ForEach(TopicRoomPostSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .listRowBackground(Color.clear)

                if posts.isEmpty {
                    ContentUnavailableView("このルームの投稿はまだありません", systemImage: "number.square")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(posts) { post in
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
                                showsOwnerActions: false,
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
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle(room.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadTopicRoomPosts(topic: topic)
        }
        .refreshable {
            await store.loadTopicRoomPosts(topic: topic)
        }
    }
}

private struct UserSearchRow: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: ProfileView(userID: user.id)) {
                HStack(spacing: AppSpacing.md) {
                    AvatarView(user: user, size: 40)
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

struct NotificationsView: View {
    @EnvironmentObject private var store: AppDataStore

    var body: some View {
        List {
            if store.notifications.isEmpty {
                ContentUnavailableView("通知はまだありません", systemImage: "bell")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.notifications) { notification in
                    NotificationRow(notification: notification)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadNotifications()
            await store.markNotificationsRead()
        }
        .refreshable {
            await store.loadNotifications()
            await store.markNotificationsRead()
        }
    }
}

private struct NotificationRow: View {
    @EnvironmentObject private var store: AppDataStore
    let notification: AppNotification

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: notification.type.systemImage)
                    .font(.headline)
                    .foregroundStyle(notification.isRead ? AppColor.textSecondary : AppColor.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(notification.text)
                        .font(.subheadline.weight(notification.isRead ? .regular : .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(DateFormatterUtil.relativeString(from: notification.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
    }

    @ViewBuilder
    private var destination: some View {
        if notification.type == .circleEntryCreated || notification.type == .circleCommentCreated {
            CircleListView()
        } else if let postID = notification.postID {
            PostDetailView(postID: postID)
        } else {
            ProfileView(userID: notification.actorID)
        }
    }
}

private extension AppNotificationType {
    var systemImage: String {
        switch self {
        case .comment:
            return "bubble.right.fill"
        case .like:
            return "heart.fill"
        case .follow:
            return "person.crop.circle.badge.plus"
        case .repost:
            return "arrow.2.squarepath"
        case .quote:
            return "quote.bubble.fill"
        case .mention:
            return "at"
        case .circleEntryCreated:
            return "circle.grid.2x2.fill"
        case .circleCommentCreated:
            return "bubble.left.and.bubble.right.fill"
        }
    }
}

private struct PostSubmittedCelebration: View {
    let token: Int
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColor.accent.opacity(isAnimating ? 0 : 0.24), lineWidth: 2)
                .frame(width: isAnimating ? 172 : 72, height: isAnimating ? 172 : 72)

            VStack(spacing: AppSpacing.sm) {
                BrandIconView(size: 58)

                VStack(spacing: AppSpacing.xxs) {
                    Text("投稿しました")
                        .font(AppFont.sectionTitle)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("タイムラインに反映されました")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColor.border, lineWidth: 0.7)
            }
            .shadow(color: AppColor.shadow, radius: 18, y: 10)
        }
        .onAppear {
            isAnimating = false
            withAnimation(.easeOut(duration: 0.9)) {
                isAnimating = true
            }
        }
        .id(token)
    }
}

private struct PostSubmittedToast: View {
    var message = "投稿しました"
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.accent)
            Text(message)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .shadow(color: AppColor.shadow, radius: 12, y: 6)
    }
}
