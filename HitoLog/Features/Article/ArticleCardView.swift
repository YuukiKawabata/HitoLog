import SwiftUI

struct ArticleCardView: View {
    @EnvironmentObject private var store: AppDataStore
    let article: Article
    let author: AppUser
    var showsOwnerActions = false
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}
    var onReport: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(destination: ArticleDetailView(article: article, author: author)) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: "doc.text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.accent)
                            .frame(width: 20, height: 20)

                        Text(article.title)
                            .font(AppFont.sectionTitle)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Menu {
                            if showsOwnerActions {
                                Button(action: onEdit) {
                                    Label("編集", systemImage: "pencil")
                                }
                                Button(role: .destructive, action: onDelete) {
                                    Label("削除", systemImage: "trash")
                                }
                            } else {
                                Button(role: .destructive, action: onReport) {
                                    Label("通報", systemImage: "flag")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("記事の操作")
                    }

                    let previewText = MarkdownBlock.plainPreview(from: article.freePreviewBody)
                    let previewMedia = InlineMedia.firstMedia(in: article.freePreviewBody)

                    if !previewText.isEmpty || previewMedia != nil {
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            if !previewText.isEmpty {
                                Text(previewText)
                                    .font(.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer(minLength: 0)
                            }

                            if let previewMedia {
                                MediaThumbnailView(media: previewMedia.postMedia, size: 64)
                            }
                        }
                    }

                    InkDivider()

                    HStack(spacing: AppSpacing.sm) {
                        AvatarView(user: author, size: 22)

                        Text(author.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if !article.isPublished {
                            draftPill
                        }

                        humanBadgePill

                        if article.price.isPaid {
                            pricePill
                        }
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Label(article.durationText + "かけて書かれた記事", systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                        Spacer(minLength: 0)
                        Label(DateFormatterUtil.relativeString(from: article.createdAt), systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .padding(AppSpacing.md)
            }
            .buttonStyle(ScaleButtonStyle(scale: 0.98))
        }
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private var humanBadgePill: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: article.humanBadge.systemImage)
                .font(.caption2)
            Text(article.humanBadge.displayText)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(article.humanBadge == .verified ? AppColor.accent : AppColor.textSecondary)
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xs)
        .background(
            article.humanBadge == .verified ? AppColor.accentSoft : AppColor.surface,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(article.humanBadge == .verified ? AppColor.accent.opacity(0.28) : AppColor.border, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var draftPill: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "tray")
                .font(.caption2)
            Text("下書き")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(AppColor.warning)
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xs)
        .background(AppColor.warning.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppColor.warning.opacity(0.32), lineWidth: 0.5)
        }
        .accessibilityLabel("下書き、未公開")
    }

    @ViewBuilder
    private var pricePill: some View {
        Text(article.price.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColor.background)
            .padding(.vertical, AppSpacing.xs)
            .padding(.horizontal, AppSpacing.xs)
            .background(AppColor.accent, in: Capsule())
    }
}
