import Foundation

@MainActor
final class ComposeArticleViewModel: ObservableObject {
    @Published var title = ""
    @Published var freePreviewBody = ""
    @Published var paidBody = ""
    @Published var price: ArticlePrice = .free
    @Published var commentPermission: CommentPermission = .everyone
    @Published private(set) var metrics = TypingMetrics()

    /// 編集中の既存記事（新規作成時は nil）。
    private(set) var editingArticle: Article?
    var isEditing: Bool { editingArticle != nil }

    private let humanScoreService = HumanScoreService()

    var hasDraft: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !freePreviewBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !freePreviewBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var humanCheckText: String {
        metrics.suspiciousBulkInputCount == 0 ? "Human Check: OK" : "Human Check: 入力確認中"
    }

    var humanBadge: HumanBadge {
        let input = HumanScoreInput(
            inputDurationMs: metrics.inputDurationMs,
            characterCount: freePreviewBody.count + paidBody.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appAttestVerified: true,
            accountAgeDays: 0,
            recentPostCount: 0
        )
        return humanScoreService.badge(for: humanScoreService.calculate(input: input))
    }

    var canSetPaidPrice: Bool { humanBadge == .verified }

    /// 既存記事を編集用に読み込む。本人入力スコア等の検証値は元記事のものを保持する。
    func load(article: Article, paidBody: String) {
        editingArticle = article
        title = article.title
        freePreviewBody = article.freePreviewBody
        self.paidBody = paidBody
        price = article.price
        commentPermission = article.commentPermission
        metrics = TypingMetrics()
    }

    func recordChange(from oldText: String, to newText: String) {
        metrics.recordChange(from: oldText, to: newText, at: Date())
    }

    func refreshMetricsDuration() {
        metrics.refreshDuration(at: Date())
    }

    func restoreDraft(from encodedDraft: String) {
        guard !encodedDraft.isEmpty,
              let data = encodedDraft.data(using: .utf8),
              let draft = try? JSONDecoder().decode(ComposeArticleDraft.self, from: data) else { return }
        title = draft.title
        freePreviewBody = draft.freePreviewBody
        paidBody = draft.paidBody
        price = draft.price
        commentPermission = draft.commentPermission
        metrics = draft.metrics
    }

    func encodedDraft() -> String {
        guard hasDraft else { return "" }
        let draft = ComposeArticleDraft(
            title: title,
            freePreviewBody: freePreviewBody,
            paidBody: paidBody,
            price: price,
            commentPermission: commentPermission,
            metrics: metrics,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(draft) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func clearDraft() {
        title = ""
        freePreviewBody = ""
        paidBody = ""
        price = .free
        commentPermission = .everyone
        metrics = TypingMetrics()
    }

    func makeArticle(
        id: String = UUID().uuidString,
        using user: AppUser,
        status: ArticleStatus
    ) -> (article: Article, paidBody: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPreview = freePreviewBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPaidBody = paidBody.trimmingCharacters(in: .whitespacesAndNewlines)

        // 既存記事の編集 — 検証値（humanBadge/score/作成日）を保持し、内容のみ更新する。
        if var updated = editingArticle {
            let combined = "\(trimmedTitle) \(trimmedPreview)"
            updated.title = trimmedTitle
            updated.freePreviewBody = trimmedPreview
            updated.status = status
            updated.price = updated.humanBadge == .verified ? price : .free
            updated.topics = TopicExtractor.topics(in: combined)
            updated.searchTokens = PostSearchTokenizer.tokens(in: combined, topics: updated.topics)
            updated.commentPermission = commentPermission
            updated.updatedAt = Date()
            return (updated, trimmedPaidBody)
        }

        let input = HumanScoreInput(
            inputDurationMs: metrics.inputDurationMs,
            characterCount: freePreviewBody.count + paidBody.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appAttestVerified: true,
            accountAgeDays: user.accountAgeDays,
            recentPostCount: 0
        )
        let score = humanScoreService.calculate(input: input)
        let badge = humanScoreService.badge(for: score)
        let now = Date()
        let effectivePrice: ArticlePrice = badge == .verified ? price : .free

        let article = Article(
            id: id,
            userID: user.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            freePreviewBody: freePreviewBody.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            price: effectivePrice,
            commentPermission: commentPermission,
            humanBadge: badge,
            humanScore: score,
            inputDurationMs: metrics.inputDurationMs,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            createdAt: now,
            updatedAt: now
        )
        return (article, paidBody.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private struct ComposeArticleDraft: Codable {
    let title: String
    let freePreviewBody: String
    let paidBody: String
    let price: ArticlePrice
    let commentPermission: CommentPermission
    let metrics: TypingMetrics
    let updatedAt: Date
}
