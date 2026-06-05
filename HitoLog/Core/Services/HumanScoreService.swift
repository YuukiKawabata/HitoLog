import Foundation

struct HumanScoreInput {
    let inputDurationMs: Int
    let characterCount: Int
    let editCount: Int
    let deleteCount: Int
    let suspiciousBulkInputCount: Int
    let appAttestVerified: Bool
    let accountAgeDays: Int
    let recentPostCount: Int
    /// AI併用を正直に開示したか。true のとき一括入力ペナルティを免除する。
    var aiAssisted: Bool = false
}

struct HumanScoreService {
    func calculate(input: HumanScoreInput) -> Int {
        var score = 100

        if !input.appAttestVerified {
            score -= 20
        }

        // 一括入力（ペースト/AI生成貼り付け）の疑い。ただし正直に「AI併用」を
        // 開示している場合は、欺瞞ではないためペナルティを科さない。
        if input.suspiciousBulkInputCount > 0 && !input.aiAssisted {
            score -= 30 * input.suspiciousBulkInputCount
        }

        let seconds = max(Double(input.inputDurationMs) / 1000.0, 1.0)
        let charsPerSecond = Double(input.characterCount) / seconds

        if input.characterCount >= 100 && charsPerSecond > 10 {
            score -= 20
        }

        if input.recentPostCount >= 10 {
            score -= 10
        }

        if input.accountAgeDays < 1 {
            score -= 5
        }

        if input.editCount > 0 || input.deleteCount > 0 {
            score += 5
        }

        return min(max(score, 0), 100)
    }

    func badge(for score: Int) -> HumanBadge {
        if score >= 80 {
            return .verified
        } else if score >= 50 {
            return .checking
        } else {
            return .lowTrust
        }
    }
}

