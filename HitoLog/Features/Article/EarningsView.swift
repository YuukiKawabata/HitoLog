import SwiftUI

struct EarningsSummaryView: View {
    let articles: [Article]
    let creatorEarnings: CreatorEarnings

    init(articles: [Article], creatorEarnings: CreatorEarnings = .empty) {
        self.articles = articles
        self.creatorEarnings = creatorEarnings
    }

    private var paidArticles: [Article] {
        articles.filter { $0.price.isPaid && $0.status == .published }
    }

    private var totalPurchases: Int {
        paidArticles.reduce(0) { $0 + $1.purchaseCount }
    }

    private var totalRevenueEvents: Int {
        max(totalPurchases, creatorEarnings.articleCount)
        + creatorEarnings.membershipCount
        + creatorEarnings.supportCount
    }

    private var totalGrossYen: Int {
        articleGrossYen + creatorEarnings.supportTotalYen + creatorEarnings.membershipMonthlyYen
    }

    private var localArticleGrossYen: Int {
        paidArticles.reduce(0) { $0 + $1.purchaseCount * $1.price.priceInYen }
    }

    private var articleGrossYen: Int {
        max(localArticleGrossYen, creatorEarnings.articleGrossYen)
    }

    private var usesLedgerArticleRevenue: Bool {
        creatorEarnings.articleGrossYen > 0
    }

    private var fallbackArticleBreakdown: MonetizationBreakdown {
        MonetizationPolicy.breakdown(grossYen: usesLedgerArticleRevenue ? 0 : localArticleGrossYen)
    }

    private var estimatedAppleFeeYen: Int {
        creatorEarnings.estimatedAppleFeeYen + fallbackArticleBreakdown.estimatedAppleFeeYen
    }

    private var platformFeeYen: Int {
        creatorEarnings.platformFeeYen + fallbackArticleBreakdown.platformFeeYen
    }

    private var creatorPayoutYen: Int {
        creatorEarnings.creatorPayoutYen + fallbackArticleBreakdown.creatorPayoutYen
    }

    private var hasRevenue: Bool {
        totalRevenueEvents > 0 || totalGrossYen > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "収益".localized, systemImage: "yensign.circle")

            if !hasRevenue {
                Text("有料記事を公開すると、ここに収益が表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    EarningsTile(
                        title: "購入/支援".localized,
                        value: L10n.format("%lld件", Int64(totalRevenueEvents)),
                        systemImage: "cart"
                    )
                    EarningsTile(
                        title: "売上（税込）".localized,
                        value: "¥\(totalGrossYen.formatted())",
                        systemImage: "yensign"
                    )
                    EarningsTile(
                        title: "振込予定額".localized,
                        value: "¥\(creatorPayoutYen.formatted())",
                        systemImage: "banknote"
                    )
                }

                HStack(spacing: AppSpacing.sm) {
                    EarningsTile(
                        title: "Apple控除".localized,
                        value: "¥\(estimatedAppleFeeYen.formatted())",
                        systemImage: "apple.logo"
                    )
                    EarningsTile(
                        title: "HitoLog手数料".localized,
                        value: "¥\(platformFeeYen.formatted())",
                        systemImage: "building.columns"
                    )
                    EarningsTile(
                        title: "保留期間".localized,
                        value: L10n.format("%lld日", Int64(MonetizationPolicy.payoutHoldDays)),
                        systemImage: "calendar.badge.clock"
                    )
                }

                HStack(spacing: AppSpacing.sm) {
                    EarningsTile(
                        title: "記事売上".localized,
                        value: "¥\(articleGrossYen.formatted())",
                        systemImage: "doc.text"
                    )
                    EarningsTile(
                        title: "サブスク月額".localized,
                        value: "¥\(creatorEarnings.membershipMonthlyYen.formatted())",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    EarningsTile(
                        title: "サポート".localized,
                        value: "¥\(creatorEarnings.supportTotalYen.formatted())",
                        systemImage: "hands.sparkles"
                    )
                }

                Text(L10n.format(
                    "振込予定額は App Store 控除（推定%lld%%）後の金額から HitoLog 手数料（%lld%%）を差し引いた目安です。返金・税・Appleの精算により実際の金額は変動します。",
                    Int64(MonetizationPolicy.estimatedAppleCommissionRatePermille / 10),
                    Int64(MonetizationPolicy.platformFeeRatePermille / 10)
                ))
                    .font(.caption2)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !paidArticles.isEmpty {
                    InkDivider()

                    ForEach(paidArticles) { article in
                        HStack(spacing: AppSpacing.sm) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(article.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                    .lineLimit(1)
                                Text(article.price.displayText)
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                                Text(L10n.format("%lld件", Int64(article.purchaseCount)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text(L10n.format("¥%@", (article.purchaseCount * article.price.priceInYen).formatted()))
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .paperSurface()
    }
}

private struct EarningsTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.sm)
        .background(AppColor.background, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}
