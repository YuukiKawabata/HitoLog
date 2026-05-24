import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: AppDataStore
    @State private var editingPost: Post?
    @State private var deletingPost: Post?

    var body: some View {
        let posts = store.timelinePosts

        ScrollView {
            LazyVStack(spacing: 0) {
                TimelineHeaderView()
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)

                if posts.isEmpty {
                    EmptyTimelineView()
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
        }
        .background(AppColor.groupedBackground)
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
                    Text("Human Timeline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.accent)
                        .textCase(.uppercase)
                    Text("いま書かれた言葉")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.textPrimary)
                }
            }

            Text("貼り付けではなく、入力の過程が残る投稿だけを集めています。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

private struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.textSecondary)

            Text("まだ投稿がありません")
                .font(.headline)

            Text("あなたの言葉で、最初の投稿をしてみましょう。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, AppSpacing.lg)
    }
}
