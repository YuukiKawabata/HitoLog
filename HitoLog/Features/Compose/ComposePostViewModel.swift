import Foundation

@MainActor
final class ComposePostViewModel: ObservableObject {
    @Published var text = ""
    @Published private(set) var metrics = TypingMetrics()
    /// 「AIの助けを借りた」ことを正直に開示するか（ユーザー操作）。
    @Published var aiAssisted = false

    private let humanScoreService = HumanScoreService()

    /// 一括入力の疑いが検知され、AI併用の開示を促すべき状態か。
    var shouldPromptAIDisclosure: Bool {
        metrics.suspiciousBulkInputCount > 0
    }

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
        aiAssisted = draft.aiAssisted
    }

    func encodedDraft() -> String {
        guard hasDraft else { return "" }
        let draft = ComposePostDraft(text: text, metrics: metrics, aiAssisted: aiAssisted, updatedAt: Date())
        guard let data = try? JSONEncoder().encode(draft) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func clearDraft() {
        text = ""
        metrics = TypingMetrics()
        aiAssisted = false
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
            recentPostCount: recentPostCount,
            aiAssisted: aiAssisted
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
            aiAssisted: aiAssisted,
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
    var aiAssisted: Bool = false
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case text, metrics, aiAssisted, updatedAt
    }

    init(text: String, metrics: TypingMetrics, aiAssisted: Bool, updatedAt: Date) {
        self.text = text
        self.metrics = metrics
        self.aiAssisted = aiAssisted
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        metrics = try container.decode(TypingMetrics.self, forKey: .metrics)
        aiAssisted = try container.decodeIfPresent(Bool.self, forKey: .aiAssisted) ?? false
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
