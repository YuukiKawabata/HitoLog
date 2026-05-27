import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var isShowingCompose = false
    @State private var isShowingPostToast = false
    @State private var celebrationToken = 0

    var body: some View {
        TabView {
            NavigationStack {
                TimelineView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house")
            }

            NavigationStack {
                UserSearchView()
            }
            .tabItem {
                Label("検索", systemImage: "magnifyingglass")
            }

            NavigationStack {
                NotificationsView()
            }
            .tabItem {
                Label("通知", systemImage: "bell")
            }
            .badge(store.unreadNotificationCount)

            NavigationStack {
                ComposeEntryView {
                    isShowingCompose = true
                }
            }
            .tabItem {
                Label("投稿", systemImage: "square.and.pencil")
            }

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("プロフィール", systemImage: "person.crop.circle")
            }
        }
        .tint(AppColor.accent)
        .sheet(isPresented: $isShowingCompose) {
            ComposePostView {
                showPostToast()
            }
        }
        .overlay(alignment: .top) {
            if isShowingPostToast {
                PostSubmittedToast()
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if isShowingPostToast {
                PostSubmittedCelebration(token: celebrationToken)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: isShowingPostToast)
    }

    private func showPostToast() {
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

private struct UserSearchView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var query = ""
    @State private var scope: SearchScope = .users
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedStarterPack: StarterPackCategory = .writers

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
                Section("スターターパック") {
                    Picker("カテゴリ", selection: $selectedStarterPack) {
                        ForEach(StarterPackCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    let starterUsers = store.starterPackUsers(for: selectedStarterPack)
                    if starterUsers.isEmpty {
                        ContentUnavailableView("候補はまだありません", systemImage: selectedStarterPack.systemImage)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(starterUsers) { user in
                            UserSearchRow(user: user)
                        }
                    }
                }

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
        case .posts:
            await store.searchPosts(query: value)
        }
    }
}

private enum SearchScope: String, CaseIterable, Identifiable {
    case users
    case topics
    case posts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .users:
            return "ユーザー"
        case .topics:
            return "話題"
        case .posts:
            return "投稿"
        }
    }

    var systemImage: String {
        switch self {
        case .users:
            return "person.2"
        case .topics:
            return "number"
        case .posts:
            return "text.magnifyingglass"
        }
    }

    var prompt: String {
        switch self {
        case .users:
            return "名前またはユーザー名"
        case .topics:
            return "#健康 など"
        case .posts:
            return "投稿本文を検索"
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

                VStack(alignment: .leading, spacing: 2) {
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

private struct UserSearchRow: View {
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

            Spacer()

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

                VStack(alignment: .leading, spacing: 4) {
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

                VStack(spacing: 2) {
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
    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppColor.accent)
            Text("投稿しました")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 10)
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

            Button(action: onComposeTap) {
                Label("投稿を書く", systemImage: "pencil")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperCanvas())
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
    }
}
