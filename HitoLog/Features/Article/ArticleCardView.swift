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
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }

                    if !article.freePreviewBody.isEmpty {
                        Text(article.freePreviewBody)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    InkDivider()

                    HStack(spacing: AppSpacing.sm) {
                        AvatarView(user: author, size: 22)

                        Text(author.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

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
            .buttonStyle(.plain)
        }
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private var humanBadgePill: some View {
        HStack(spacing: 3) {
            Image(systemName: article.humanBadge.systemImage)
                .font(.caption2)
            Text(article.humanBadge.displayText)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(article.humanBadge == .verified ? AppColor.accent : AppColor.textSecondary)
        .padding(.vertical, 3)
        .padding(.horizontal, AppSpacing.xs)
        .background(
            article.humanBadge == .verified ? AppColor.accentSoft : AppColor.surface,
            in: Capsule()
        )
    }

    @ViewBuilder
    private var pricePill: some View {
        Text(article.price.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColor.background)
            .padding(.vertical, 3)
            .padding(.horizontal, AppSpacing.xs)
            .background(AppColor.accent, in: Capsule())
    }
}
