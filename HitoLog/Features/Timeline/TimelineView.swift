import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var editingPost: Post?
    @State private var deletingPost: Post?
    @State private var selectedFilter: TimelineFilter = .all

    var body: some View {
        let posts = selectedFilter == .all ? store.timelinePosts : store.followingTimelinePosts

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

                if posts.isEmpty {
                    EmptyTimelineView(
                        title: selectedFilter.emptyTitle,
                        message: selectedFilter.emptyMessage
                    )
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, 96)
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
}

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "すべて"
        case .following:
            return "フォロー中"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            return "まだ表示できる投稿がありません"
        case .following:
            return "フォロー中の投稿はまだありません"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all:
            return "他の人の投稿が届くと、ここに表示されます。"
        case .following:
            return "気になる人をフォローすると、ここに投稿が表示されます。"
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
