import SwiftUI

struct ArticleDetailView: View {
    @EnvironmentObject private var store: AppDataStore
    let article: Article
    let author: AppUser
    @State private var paidBody: String?
    @State private var isLoadingBody = false
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var showsPurchaseError = false
    @State private var showsReportConfirmation = false

    private var isOwner: Bool { article.userID == store.currentUser.id }
    private var isUnlocked: Bool { isOwner || store.isUnlocked(article.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                articleHeader
                freeContent
                if article.price.isPaid {
                    paidSection
                } else {
                    fullBodySection
                }
            }
            .padding(.bottom, AppSpacing.xl)
        }
        .background(PaperCanvas())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBodyIfNeeded()
        }
        .alert("購入エラー", isPresented: $showsPurchaseError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseError ?? "不明なエラーが発生しました")
        }
        .confirmationDialog("この記事を通報しますか？", isPresented: $showsReportConfirmation, titleVisibility: .visible) {
            Button("通報する", role: .destructive) {
                store.addReport(
                    targetType: .article,
                    targetID: article.id,
                    targetOwnerID: article.userID,
                    targetDescription: "記事: \(article.title.prefix(40))",
                    reason: "不適切な記事"
                )
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("通報は運営が確認します。悪用防止のため、通報は慎重にお願いします。")
        }
        .toolbar {
            if !isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsReportConfirmation = true
                    } label: {
                        Image(systemName: "flag")
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "Article", systemImage: "doc.text")

            Text(article.title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            InkDivider()

            HStack(spacing: AppSpacing.sm) {
                AvatarView(user: author, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(author.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("@\(author.handle)")
                        .font(.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                Spacer(minLength: 0)
                NavigationLink(destination: ProfileView(userID: author.id)) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(AppColor.textSecondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: AppSpacing.md) {
                Label(article.durationText + "かけて書かれた記事", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Label("\(article.editCount)回編集", systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            HStack(spacing: AppSpacing.sm) {
                humanBadgeChip
                if article.price.isPaid {
                    priceBadge
                }
                Spacer(minLength: 0)
                Text(DateFormatterUtil.relativeString(from: article.createdAt))
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
    }

    private var freeContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(article.freePreviewBody)
                .font(AppFont.body)
                .lineSpacing(6)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private var fullBodySection: some View {
        if isLoadingBody {
            ProgressView("本文を読み込み中")
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.xl)
                .paperSurface()
                .padding(.horizontal, AppSpacing.md)
        } else if let body = paidBody, !body.isEmpty {
            bodyText(body)
        }
    }

    @ViewBuilder
    private var paidSection: some View {
        if isUnlocked {
            if isLoadingBody {
                ProgressView("本文を読み込み中")
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.xl)
                    .paperSurface()
                    .padding(.horizontal, AppSpacing.md)
            } else if let body = paidBody, !body.isEmpty {
                bodyText(body)
            }
        } else {
            paywallView
        }
    }

    private func bodyText(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(body)
                .font(AppFont.body)
                .lineSpacing(6)
                .foregroundStyle(AppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.md)
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
    }

    private var paywallView: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "lock.doc")
                .font(.system(size: 32))
                .foregroundStyle(AppColor.accent)

            Text("続きは\(article.price.displayText)で読めます")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)

            Text("購入すると、この記事の全文を永久に読み続けることができます。返金は対応していません。")
                .font(.subheadline)
                .foregroundStyle(AppColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await purchase() }
            } label: {
                if isPurchasing {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView().tint(AppColor.background)
                        Text("購入処理中")
                    }
                } else {
                    Label("続きを購入（\(article.price.displayText)）", systemImage: "cart")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isPurchasing || store.currentUser.isSuspended)

            if article.purchaseCount > 0 {
                Label("\(article.purchaseCount)人が購入済み", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .paperSurface()
        .padding(.horizontal, AppSpacing.md)
    }

    @ViewBuilder
    private var humanBadgeChip: some View {
        HStack(spacing: 3) {
            Image(systemName: article.humanBadge.systemImage)
                .font(.caption2)
            Text(article.humanBadge.displayText)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(article.humanBadge == .verified ? AppColor.accent : AppColor.textSecondary)
        .padding(.vertical, 4)
        .padding(.horizontal, AppSpacing.xs)
        .background(
            article.humanBadge == .verified ? AppColor.accentSoft : AppColor.surface,
            in: Capsule()
        )
    }

    @ViewBuilder
    private var priceBadge: some View {
        Text(article.price.displayText)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColor.background)
            .padding(.vertical, 4)
            .padding(.horizontal, AppSpacing.xs)
            .background(AppColor.accent, in: Capsule())
    }

    private func loadBodyIfNeeded() async {
        guard paidBody == nil, !isLoadingBody else { return }
        guard !article.price.isPaid || isUnlocked else { return }
        isLoadingBody = true
        defer { isLoadingBody = false }
        paidBody = try? await store.loadArticleBody(articleID: article.id)
    }

    @MainActor
    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let purchased = try await store.purchaseArticle(article)
            if purchased {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Load body now that we have access
                isLoadingBody = true
                paidBody = try? await store.loadArticleBody(articleID: article.id)
                isLoadingBody = false
            }
        } catch {
            purchaseError = error.localizedDescription
            showsPurchaseError = true
        }
    }
}
