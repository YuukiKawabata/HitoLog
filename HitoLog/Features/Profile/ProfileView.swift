import SwiftUI

private enum ProfileTab: String, CaseIterable, Identifiable {
    case posts
    case articles
    case saved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: return "投稿"
        case .articles: return "記事"
        case .saved: return "保存"
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "text.bubble"
        case .articles: return "doc.text"
        case .saved: return "bookmark"
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: AppDataStore
    let userID: String?
    @State private var editingPost: Post?
    @State private var deletingPost: Post?
    @State private var editingArticle: Article?
    @State private var deletingArticle: Article?
    @State private var profileTab: ProfileTab = .posts
    @State private var monetizationErrorMessage: String?

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
                            postCount: store.postCount(for: user.id),
                            stats: stats(for: user)
                        )
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)

                        if MonetizationPolicy.isEnabled {
                            CreatorMonetizationPanel(
                                user: user,
                                isPreview: user.id == store.currentUser.id,
                                onMembership: { plan in
                                    Task { await purchaseMembership(plan, creator: user) }
                                },
                                onSupport: { amount in
                                    Task { await purchaseSupport(amount, recipient: user) }
                                }
                            )
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.bottom, AppSpacing.sm)
                        }

                        if let highlight = representativePost(for: user) {
                            RepresentativeWorkCard(post: highlight, author: user)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.bottom, AppSpacing.sm)
                        }

                        Picker("表示", selection: $profileTab) {
                            ForEach(ProfileTab.allCases) { tab in
                                Label(tab.title, systemImage: tab.systemImage).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)

                        Group {
                            switch profileTab {
                            case .posts:
                                postsSection(for: user)
                            case .articles:
                                articlesSection(for: user)
                            case .saved:
                                savedSection
                            }
                        }
                        .id(profileTab)
                        .transition(.opacity)
                    }
                    .animation(.easeInOut(duration: 0.2), value: profileTab)
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
        .sheet(item: $editingArticle) { article in
            ComposeArticleView(editingArticle: article)
                .environmentObject(store)
        }
        .confirmationDialog(
            "記事を削除しますか？",
            isPresented: Binding(
                get: { deletingArticle != nil },
                set: { isPresented in if !isPresented { deletingArticle = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let deletingArticle {
                    store.deleteArticle(articleID: deletingArticle.id)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                deletingArticle = nil
            }
            Button("キャンセル", role: .cancel) { deletingArticle = nil }
        } message: {
            Text("削除した記事は元に戻せません。")
        }
        .confirmationDialog(
            "投稿を削除しますか？",
            isPresented: Binding(
                get: { deletingPost != nil },
                set: { isPresented in if !isPresented { deletingPost = nil } }
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
            Button("キャンセル", role: .cancel) { deletingPost = nil }
        } message: {
            Text("削除した投稿はタイムラインに表示されなくなります。")
        }
        .alert("購入できません", isPresented: Binding(
            get: { monetizationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    monetizationErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(monetizationErrorMessage ?? "通信状態を確認して、もう一度お試しください。")
        }
        .task {
            if let user = displayedUser {
                await store.loadUserArticles(userID: user.id)
                if MonetizationPolicy.isEnabled && user.id == store.currentUser.id {
                    await store.loadCreatorEarnings()
                }
            }
        }
    }

    @ViewBuilder
    private func postsSection(for user: AppUser) -> some View {
        let posts = store.visibleProfilePosts(for: user.id)
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
        }
    }

    @ViewBuilder
    private func articlesSection(for user: AppUser) -> some View {
        let articles = store.profileArticles(for: user.id)
        let isOwner = user.id == store.currentUser.id
        if articles.isEmpty {
            ContentUnavailableView("記事がありません", systemImage: "doc.text")
                .padding(.top, AppSpacing.xl)
        } else {
            LazyVStack(spacing: AppSpacing.sm) {
                if MonetizationPolicy.isEnabled && isOwner {
                    EarningsSummaryView(articles: articles, creatorEarnings: store.creatorEarnings)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.sm)
                }
                ForEach(articles) { article in
                    ArticleCardView(
                        article: article,
                        author: user,
                        showsOwnerActions: isOwner,
                        onEdit: { editingArticle = article },
                        onDelete: { deletingArticle = article },
                        onReport: {
                            guard !isOwner else { return }
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
            .padding(.vertical, AppSpacing.sm)
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        BookmarkedPostsView(inline: true)
    }

    private func stats(for user: AppUser) -> ProfileStats {
        ProfileStats(
            posts: store.visibleProfilePosts(for: user.id),
            articles: store.profileArticles(for: user.id)
        )
    }

    private func representativePost(for user: AppUser) -> Post? {
        store.visibleProfilePosts(for: user.id)
            .filter { ($0.likeCount + $0.commentCount) > 0 }
            .max { ($0.likeCount + $0.commentCount) < ($1.likeCount + $1.commentCount) }
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

    @MainActor
    private func purchaseMembership(_ plan: CreatorMembershipPlan, creator: AppUser) async {
        do {
            let purchased = try await store.purchaseCreatorMembership(creatorID: creator.id, plan: plan)
            if purchased {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            monetizationErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func purchaseSupport(_ amount: SupportAmount, recipient: AppUser) async {
        do {
            let purchased = try await store.purchaseSupport(recipientID: recipient.id, amount: amount)
            if purchased {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            monetizationErrorMessage = error.localizedDescription
        }
    }
}

private struct CreatorMonetizationPanel: View {
    let user: AppUser
    let isPreview: Bool
    let onMembership: (CreatorMembershipPlan) -> Void
    let onSupport: (SupportAmount) -> Void
    @State private var showsPreviewNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if isPreview {
                HStack(spacing: AppSpacing.xs) {
                    SectionKicker(text: "支援導線プレビュー", systemImage: "eye")
                    Spacer(minLength: 0)
                    Text("プレビュー")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppColor.accent)
                        .padding(.vertical, AppSpacing.xxs)
                        .padding(.horizontal, AppSpacing.sm)
                        .background(AppColor.accentSoft, in: Capsule())
                }

                Text("ほかのユーザーには、このプロフィールにメンバーシップとサポートの導線が表示されます。")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppSpacing.sm) {
                Menu {
                    ForEach(CreatorMembershipPlan.allCases) { plan in
                        Button {
                            handleMembership(plan)
                        } label: {
                            Label(plan.displayText, systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                } label: {
                    Label("メンバー", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())

                Menu {
                    ForEach(SupportAmount.allCases) { amount in
                        Button {
                            handleSupport(amount)
                        } label: {
                            Label(amount.displayText, systemImage: "hands.sparkles")
                        }
                    }
                } label: {
                    Label("サポート", systemImage: "hands.sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(AppSpacing.md)
        .background(AppColor.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(user.displayName)をサポート")
        .alert("プレビュー", isPresented: $showsPreviewNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("自分のプロフィールでは購入処理は実行されません。")
        }
    }

    private func handleMembership(_ plan: CreatorMembershipPlan) {
        guard !isPreview else {
            showsPreviewNotice = true
            return
        }
        onMembership(plan)
    }

    private func handleSupport(_ amount: SupportAmount) {
        guard !isPreview else {
            showsPreviewNotice = true
            return
        }
        onSupport(amount)
    }
}

private struct ProfileHeaderView: View {
    @EnvironmentObject private var store: AppDataStore
    let user: AppUser
    let postCount: Int
    let stats: ProfileStats

    private let avatarSize: CGFloat = 84
    private let coverHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            coverBanner

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                identityRow

                if user.id != store.currentUser.id && !store.blockedUserIDs.contains(user.id) {
                    followButton
                } else if store.blockedUserIDs.contains(user.id) {
                    Label("ブロック中", systemImage: "hand.raised")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.warning)
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.sm)
                        .background(AppColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }

                if !user.bio.isEmpty {
                    Text(InlineRichText.attributedBody(user.bio))
                        .font(AppFont.body)
                        .lineSpacing(5)
                        .foregroundStyle(AppColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .tint(AppColor.accent)
                }

                detailInfoRow

                writingStory

                countsRow

                trustCard

                if !stats.topTopics.isEmpty {
                    topicsRow
                }

                followedTopicsRow
            }
            .padding(AppSpacing.md)
        }
        .background(AppColor.background)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.7)
        }
        .shadow(color: AppColor.shadow, radius: 14, x: 0, y: 8)
    }

    private var coverBanner: some View {
        LinearGradient(
            colors: [AppColor.accentSoft, AppColor.surface, AppColor.subBackground],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            CoverRulePattern()
                .opacity(0.5)
        }
        .frame(height: coverHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            AvatarView(user: user, size: avatarSize)
                .padding(.leading, AppSpacing.md)
                .offset(y: avatarSize / 2)
        }
    }

    private var identityRow: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
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
                HumanBadgeView(badge: user.derivedHumanBadge)
                    .padding(.top, AppSpacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if user.id != store.currentUser.id {
                reportMenu
            }
        }
        .padding(.top, avatarSize / 2 + AppSpacing.xs)
    }

    private var writingStory: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.semibold))
            Text(joinedText)
            Text("·")
            Text("開設\(user.accountAgeDays)日")
        }
        .font(.caption)
        .foregroundStyle(AppColor.textSecondary)
    }

    private var countsRow: some View {
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
    }

    private var trustCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                SectionKicker(text: "執筆の記録", systemImage: "signature")
                Spacer(minLength: 0)
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2.weight(.bold))
                    Text("Lv.\(user.humanLevel)")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(AppColor.accent)
                .padding(.vertical, AppSpacing.xxs)
                .padding(.horizontal, AppSpacing.sm)
                .background(AppColor.accentSoft, in: Capsule())
            }

            HStack(spacing: AppSpacing.sm) {
                ProfileFigureTile(
                    title: "つづった文字",
                    value: stats.totalCharacters.formatted(.number.grouping(.automatic)),
                    unit: "字",
                    systemImage: "character.cursor.ibeam"
                )
                ProfileFigureTile(
                    title: "公開記事",
                    value: "\(stats.publishedArticleCount)",
                    unit: "本",
                    systemImage: "doc.text"
                )
                ProfileFigureTile(
                    title: "連続記録",
                    value: "\(stats.streakDays)",
                    unit: "日",
                    systemImage: "flame"
                )
            }

            HStack(spacing: AppSpacing.sm) {
                ProfileFigureTile(
                    title: "受け取ったいいね",
                    value: stats.likesReceived.formatted(.number.grouping(.automatic)),
                    unit: "件",
                    systemImage: "heart"
                )
                ProfileFigureTile(
                    title: "受け取ったコメント",
                    value: stats.commentsReceived.formatted(.number.grouping(.automatic)),
                    unit: "件",
                    systemImage: "bubble.right"
                )
                ProfileFigureTile(
                    title: "綴った時間",
                    value: stats.writingTimeValue,
                    unit: stats.writingTimeUnit,
                    systemImage: "timer"
                )
            }

            ProfileGauge(
                title: "本人入力投稿率",
                systemImage: "checkmark.seal.fill",
                progress: user.humanVerifiedPostRate
            )
        }
        .padding(AppSpacing.md)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.border, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var detailInfoRow: some View {
        let items = detailItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(items, id: \.text) { item in
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: item.systemImage)
                            .font(.caption2.weight(.semibold))
                            .frame(width: 16)
                        if let url = item.url {
                            Link(item.text, destination: url)
                                .tint(AppColor.accent)
                        } else {
                            Text(item.text)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var detailItems: [(systemImage: String, text: String, url: URL?)] {
        var items: [(systemImage: String, text: String, url: URL?)] = []
        if let occupation = user.occupation, !occupation.isEmpty {
            items.append(("briefcase", occupation, nil))
        }
        if let location = user.location, !location.isEmpty {
            items.append(("mappin.and.ellipse", location, nil))
        }
        if let display = user.websiteDisplayText, let url = user.websiteURL {
            items.append(("link", display, url))
        }
        return items
    }

    @ViewBuilder
    private var followedTopicsRow: some View {
        let topics = store.followedTopicIDs.sorted()
        if user.id == store.currentUser.id && !topics.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionKicker(text: "フォロー中の話題", systemImage: "bell.badge")
                FlowChips(topics: Array(topics.prefix(10)))
            }
        }
    }

    private var topicsRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionKicker(text: "よく綴る話題", systemImage: "number")
            FlowChips(topics: stats.topTopics)
        }
    }

    private var joinedText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月"
        return "\(formatter.string(from: user.createdAt))から綴っています"
    }

    private var followButton: some View {
        FollowPillButton(isFollowing: store.isFollowing(user.id), size: .prominent) {
            store.toggleFollow(userID: user.id)
        }
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
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("その他の操作")
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

private struct ProfileFigureTile: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.accent)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

private struct ProfileGauge: View {
    let title: String
    let systemImage: String
    let progress: Double

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer(minLength: 0)
                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.border.opacity(0.45))
                    Capsule()
                        .fill(AppColor.accent)
                        .frame(width: max(proxy.size.width * clamped, clamped > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
    }
}

private struct FlowChips: View {
    let topics: [String]

    var body: some View {
        FlexibleChipLayout(spacing: AppSpacing.xs) {
            ForEach(topics, id: \.self) { topic in
                TopicChip(topic: topic)
            }
        }
    }
}

/// シンプルな折り返しレイアウト（チップを左詰めで横並び、はみ出したら次の行へ）
private struct FlexibleChipLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthWithSpacing = (rows[rows.count - 1].isEmpty ? 0 : spacing) + size.width
            if currentRowWidth + widthWithSpacing > maxWidth && !rows[rows.count - 1].isEmpty {
                totalHeight += rowHeight + spacing
                rows.append([subview])
                currentRowWidth = size.width
                rowHeight = size.height
            } else {
                rows[rows.count - 1].append(subview)
                currentRowWidth += widthWithSpacing
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? currentRowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct CoverRulePattern: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 14
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 18
                }
            }
            .stroke(AppColor.ruleLine, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// プロフィール表示用に投稿・記事を集計した指標
private struct ProfileStats {
    let totalCharacters: Int
    let publishedArticleCount: Int
    let topTopics: [String]
    let likesReceived: Int
    let commentsReceived: Int
    let writingMinutes: Int
    let streakDays: Int

    init(posts: [Post], articles: [Article]) {
        let postChars = posts.reduce(0) { $0 + $1.body.count }
        let articleChars = articles.reduce(0) { $0 + $1.title.count + $1.freePreviewBody.count }
        totalCharacters = postChars + articleChars
        publishedArticleCount = articles.filter(\.isPublished).count

        likesReceived = posts.reduce(0) { $0 + $1.likeCount }
        commentsReceived = posts.reduce(0) { $0 + $1.commentCount } + articles.reduce(0) { $0 + $1.commentCount }

        let totalMs = posts.reduce(0) { $0 + $1.inputDurationMs } + articles.reduce(0) { $0 + $1.inputDurationMs }
        writingMinutes = totalMs / 60_000

        streakDays = ProfileStats.consecutiveDays(from: posts.map(\.createdAt))

        var counts: [String: Int] = [:]
        for topic in posts.flatMap(\.topics) + articles.flatMap(\.topics) {
            counts[topic, default: 0] += 1
        }
        topTopics = counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(6)
            .map(\.key)
    }

    /// 今日（または昨日）から遡って連続して投稿がある日数
    private static func consecutiveDays(from dates: [Date]) -> Int {
        guard !dates.isEmpty else { return 0 }
        let calendar = Calendar.current
        let postedDays = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: Date())

        // 起点は今日。今日まだ投稿が無ければ昨日から数える（連続が途切れていなければ）
        var cursor = today
        if !postedDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  postedDays.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while postedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    var writingTimeValue: String {
        if writingMinutes >= 60 {
            let hours = Double(writingMinutes) / 60
            return hours.formatted(.number.precision(.fractionLength(hours >= 10 ? 0 : 1)))
        }
        return "\(writingMinutes)"
    }

    var writingTimeUnit: String {
        writingMinutes >= 60 ? "時間" : "分"
    }
}

private struct RepresentativeWorkCard: View {
    let post: Post
    let author: AppUser

    var body: some View {
        NavigationLink {
            PostDetailView(postID: post.id)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                SectionKicker(text: "代表する言葉", systemImage: "quote.opening")

                Text(post.body)
                    .font(AppFont.body)
                    .lineSpacing(5)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: AppSpacing.md) {
                    Label("\(post.likeCount)", systemImage: "heart.fill")
                    Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                    Spacer(minLength: 0)
                    Text(DateFormatterUtil.relativeString(from: post.createdAt))
                }
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(AppColor.accent.opacity(0.22), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension AppUser {
    /// 本人入力率から信頼バッジを導出（固定 .verified を廃止）
    var derivedHumanBadge: HumanBadge {
        if humanVerifiedPostRate >= 0.8 {
            return .verified
        } else if humanVerifiedPostRate >= 0.4 {
            return .checking
        } else {
            return .lowTrust
        }
    }
}

private struct BookmarkedPostsView: View {
    @EnvironmentObject private var store: AppDataStore
    var inline: Bool = false

    var body: some View {
        let content = LazyVStack(spacing: AppSpacing.sm) {
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

        if inline {
            content
                .padding(.vertical, AppSpacing.sm)
                .task { await store.loadBookmarkedPosts() }
        } else {
            ScrollView {
                content.padding(.vertical, AppSpacing.md)
            }
            .background(PaperCanvas())
            .navigationTitle("ブックマーク")
            .navigationBarTitleDisplayMode(.inline)
            .task { await store.loadBookmarkedPosts() }
            .refreshable { await store.loadBookmarkedPosts() }
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

            Spacer(minLength: AppSpacing.sm)

            if user.id != store.currentUser.id {
                FollowPillButton(isFollowing: store.isFollowing(user.id)) {
                    store.toggleFollow(userID: user.id)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
