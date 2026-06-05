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

    private var totalGrossYen: Int {
        articleGrossYen + creatorEarnings.supportTotalYen + creatorEarnings.membershipMonthlyYen
    }

    private var articleGrossYen: Int {
        paidArticles.reduce(0) { $0 + $1.purchaseCount * $1.price.priceInYen }
    }

    private var estimatedNetYen: Int {
        Int(Double(totalGrossYen) * 0.7)
    }

    private var hasRevenue: Bool {
        totalPurchases > 0 || creatorEarnings.membershipMonthlyYen > 0 || creatorEarnings.supportTotalYen > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionKicker(text: "Earnings", systemImage: "yensign.circle")

            if !hasRevenue {
                Text("有料記事を公開すると、ここに収益が表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: AppSpacing.sm) {
                    EarningsTile(
                        title: "総購入数",
                        value: "\(totalPurchases)件",
                        systemImage: "cart"
                    )
                    EarningsTile(
                        title: "売上（税込）",
                        value: "¥\(totalGrossYen.formatted())",
                        systemImage: "yensign"
                    )
                    EarningsTile(
                        title: "推定受取額",
                        value: "¥\(estimatedNetYen.formatted())",
                        systemImage: "banknote"
                    )
                }

                HStack(spacing: AppSpacing.sm) {
                    EarningsTile(
                        title: "記事売上",
                        value: "¥\(articleGrossYen.formatted())",
                        systemImage: "doc.text"
                    )
                    EarningsTile(
                        title: "サブスク月額",
                        value: "¥\(creatorEarnings.membershipMonthlyYen.formatted())",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                    EarningsTile(
                        title: "サポート",
                        value: "¥\(creatorEarnings.supportTotalYen.formatted())",
                        systemImage: "hands.sparkles"
                    )
                }

                Text("推定受取額は App Store 手数料（30%）控除後の目安です。実際の受取額は Apple の規定により異なる場合があります。")
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
                                Text("\(article.purchaseCount)件")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColor.textPrimary)
                                Text("¥\((article.purchaseCount * article.price.priceInYen).formatted())")
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
