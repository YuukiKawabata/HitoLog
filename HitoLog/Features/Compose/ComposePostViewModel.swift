import Foundation

@MainActor
final class ComposePostViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var metrics = TypingMetrics()

    private let humanScoreService = HumanScoreService()

    var hasDraft: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSubmit: Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedText.isEmpty && trimmedText.count <= AppConstants.maxPostLength
    }

    var humanCheckText: String {
        metrics.suspiciousBulkInputCount == 0 ? "Human Check: OK" : "Human Check: 入力確認中"
    }

    var remainingCharacters: Int {
        AppConstants.maxPostLength - text.count
    }

    var characterCountText: String {
        "\(text.count)/\(AppConstants.maxPostLength)"
    }

    var isNearLimit: Bool {
        remainingCharacters <= 40
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
              let draft = try? JSONDecoder().decode(ComposePostDraft.self, from: data) else {
            return
        }

        text = draft.text
        metrics = draft.metrics
    }

    func encodedDraft() -> String {
        guard hasDraft else { return "" }
        let draft = ComposePostDraft(text: text, metrics: metrics, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func clearDraft() {
        text = ""
        metrics = TypingMetrics()
    }

    func makePost(
        id: String = UUID().uuidString,
        using user: AppUser,
        recentPostCount: Int,
        mediaItems: [PostMedia] = [],
        commentPermission: CommentPermission = .everyone
    ) -> Post {
        let input = HumanScoreInput(
            inputDurationMs: metrics.inputDurationMs,
            characterCount: text.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appAttestVerified: true,
            accountAgeDays: user.accountAgeDays,
            recentPostCount: recentPostCount
        )
        let score = humanScoreService.calculate(input: input)
        let now = Date()

        return Post(
            id: id,
            userId: user.id,
            body: text.trimmingCharacters(in: .whitespacesAndNewlines),
            mediaItems: mediaItems,
            commentPermission: commentPermission,
            humanScore: score,
            humanBadge: humanScoreService.badge(for: score),
            inputDurationMs: metrics.inputDurationMs,
            characterCount: text.count,
            editCount: metrics.editCount,
            deleteCount: metrics.deleteCount,
            suspiciousBulkInputCount: metrics.suspiciousBulkInputCount,
            appCheckVerified: true,
            likeCount: 0,
            commentCount: 0,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
    }
}

private struct ComposePostDraft: Codable {
    let text: String
    let metrics: TypingMetrics
    let updatedAt: Date
}
