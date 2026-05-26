import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var editingPost: Post?
    @State private var deletingPost: Post?

    var body: some View {
        let posts = store.timelinePosts

        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                TimelineHeaderView()
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xs)

                if posts.isEmpty {
                    EmptyTimelineView()
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, 96)
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
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.accent)

            Text("まだ投稿がありません")
                .font(AppFont.sectionTitle)

            Text("あなたの言葉で、最初の投稿をしてみましょう。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .paperSurface()
    }
}
