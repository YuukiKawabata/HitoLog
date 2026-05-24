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
}

struct HumanScoreService {
    func calculate(input: HumanScoreInput) -> Int {
        var score = 100

        if !input.appAttestVerified {
            score -= 20
        }

        if input.suspiciousBulkInputCount > 0 {
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

