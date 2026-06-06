import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: AppDataStore
    @EnvironmentObject private var analytics: AnalyticsService
    @State private var selectedTab: MainTab = .home
    @State private var isShowingCompose = false
    @State private var isShowingArticleCompose = false
    @State private var isShowingPostToast = false
    @State private var celebrationToken = 0
    @State private var toastMessage = "投稿しました"
    @State private var toastSystemImage = "checkmark.circle.fill"
    @State private var toastShowsCelebration = true

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TimelineView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }
            .tag(MainTab.home)

            NavigationStack {
                UserSearchView()
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }
            .tag(MainTab.search)

            NavigationStack {
                NotificationsView()
            }
            .tabItem {
                Label("通知", systemImage: "bell")
            }
            .badge(store.unreadNotificationCount)
            .tag(MainTab.notifications)

            NavigationStack {
                ComposeEntryView(
                    onComposeTap: { isShowingCompose = true },
                    onArticleTap: { isShowingArticleCompose = true }
                )
            }
            .tabItem {
                Label("投稿", systemImage: "square.and.pencil")
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
        .sheet(isPresented: $isShowingArticleCompose) {
            ComposeArticleView { status in
                if status == .published {
                    showCompletionToast(message: "記事を公開しました", systemImage: "checkmark.circle.fill", celebration: true)
                } else {
                    showCompletionToast(message: "下書きを保存しました", systemImage: "tray.and.arrow.down.fill", celebration: false)
                }
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
            analytics.screen(tab.analyticsName)
        }
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

private enum MainTab: String {
    case home
    case search
    case notifications
    case compose
    case profile

    var analyticsName: String {
        switch self {
        case .home:
            return "timeline"
        case .search:
            return "search"
        case .notifications:
            return "notifications"
        case .compose:
            return "compose_entry"
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
                                            targetDescription: "投稿: \(post.body.prefix(40))",
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
            } else if scope == .articles && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("記事検索") {
                    ContentUnavailableView("キーワードで記事を検索できます", systemImage: "doc.text.magnifyingglass")
                        .listRowBackground(Color.clear)
                }
            } else if scope == .articles {
                Section("記事検索") {
                    if store.articleSearchResults.isEmpty {
                        ContentUnavailableView("記事が見つかりません", systemImage: "doc.text.magnifyingglass")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.articleSearchResults) { article in
                            if let author = store.user(for: article.userID) {
                                ArticleCardView(article: article, author: author)
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
                                            targetDescription: "投稿: \(post.body.prefix(40))",
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
        return "話題検索"
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
        case .articles:
            await store.searchArticles(query: value)
        }
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case users
    case topics
    case rooms
    case posts
    case articles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .users: return "ユーザー"
        case .topics: return "話題"
        case .rooms: return "ルーム"
        case .posts: return "投稿"
        case .articles: return "記事"
        }
    }

    var systemImage: String {
        switch self {
        case .users: return "person.2"
        case .topics: return "number"
        case .rooms: return "number.square"
        case .posts: return "text.magnifyingglass"
        case .articles: return "doc.text.magnifyingglass"
        }
    }

    var prompt: String {
        switch self {
        case .users: return "名前またはユーザー名"
        case .topics: return "#健康 など"
        case .rooms: return "ルーム名または#topic"
        case .posts: return "投稿本文を検索"
        case .articles: return "記事タイトルを検索"
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
                    Text("\(trend.postCount)件の投稿")
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
                        Text("\(room.postCount)件の投稿 ・ \(room.followerCount)人がフォロー")
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

private enum TopicRoomTab: String, CaseIterable, Identifiable {
    case posts, articles
    var id: String { rawValue }
    var title: String { self == .posts ? "投稿" : "記事" }
    var systemImage: String { self == .posts ? "text.bubble" : "doc.text" }
}

struct TopicRoomView: View {
    @EnvironmentObject private var store: AppDataStore
    let topic: String
    @State private var sort: TopicRoomPostSort = .latest
    @State private var roomTab: TopicRoomTab = .posts

    var body: some View {
        let room = store.topicRoom(for: topic)
        let posts = store.topicRoomPosts(for: topic, sort: sort)
        let roomArticles = store.topicRoomArticles(for: topic)

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
                            SectionKicker(text: "Topic Room", systemImage: "person.3")
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

            Section {
                Picker("コンテンツ", selection: $roomTab) {
                    ForEach(TopicRoomTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if roomTab == .posts {
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
                                            targetDescription: "投稿: \(post.body.prefix(40))",
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
                } else {
                    if roomArticles.isEmpty {
                        ContentUnavailableView("このルームの記事はまだありません", systemImage: "doc.text")
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(roomArticles) { article in
                            if let author = store.user(for: article.userID) {
                                ArticleCardView(
                                    article: article,
                                    author: author,
                                    showsOwnerActions: article.userID == store.currentUser.id,
                                    onReport: {
                                        guard article.userID != store.currentUser.id else { return }
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
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
            } header: {
                Text(roomTab == .posts ? "投稿" : "記事")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperCanvas())
        .navigationTitle(room.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let posts: () = store.loadTopicRoomPosts(topic: topic)
            async let articles: () = store.loadTopicRoomArticles(topic: topic)
            _ = await (posts, articles)
        }
        .refreshable {
            async let posts: () = store.loadTopicRoomPosts(topic: topic)
            async let articles: () = store.loadTopicRoomArticles(topic: topic)
            _ = await (posts, articles)
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

private struct NotificationsView: View {
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
        if let postID = notification.postID {
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

private struct ComposeEntryView: View {
    let onComposeTap: () -> Void
    let onArticleTap: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {
                BrandIconView(size: 78)

                SectionKicker(text: "Draft Desk", systemImage: "pencil.line")

                Text("いま、あなたの言葉で。")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.textPrimary)

                Text("一息ぶんの沈黙も、書き直した跡も、あなたの言葉の一部として残ります。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                InkDivider()
            }
            .padding(AppSpacing.lg)
            .paperSurface()

            VStack(spacing: AppSpacing.md) {
                Button(action: onComposeTap) {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "pencil")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .foregroundStyle(AppColor.accent)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("投稿を書く")
                                .font(AppFont.button)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("短文・いいね・リポスト")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(AppSpacing.md)
                    .paperSurface()
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.97))

                Button(action: onArticleTap) {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "doc.text")
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .background(AppColor.accentSoft, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                            .foregroundStyle(AppColor.accent)

                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text("記事を書く")
                                .font(AppFont.button)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("長文・Human Check・本人入力")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(AppSpacing.md)
                    .paperSurface()
                }
                .buttonStyle(ScaleButtonStyle(scale: 0.97))
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperCanvas())
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
    }
}
