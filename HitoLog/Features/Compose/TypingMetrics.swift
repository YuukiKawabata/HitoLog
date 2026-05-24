import Foundation

struct TypingMetrics: Equatable, Codable {
    private(set) var inputStartedAt: Date?
    private(set) var inputEndedAt: Date?
    private(set) var inputDurationMs = 0
    private(set) var characterCount = 0
    private(set) var editCount = 0
    private(set) var deleteCount = 0
    private(set) var maxCharsPerSecond = 0.0
    private(set) var suspiciousBulkInputCount = 0

    var durationText: String {
        let seconds = inputDurationMs / 1000
        return "\(seconds)秒"
    }

    mutating func recordChange(from oldText: String, to newText: String, at date: Date) {
        if inputStartedAt == nil, !newText.isEmpty {
            inputStartedAt = date
        }

        inputEndedAt = date
        characterCount = newText.count

        let delta = newText.count - oldText.count
        if delta > 0 {
            editCount += 1
        } else if delta < 0 {
            deleteCount += 1
        }

        updateDuration(at: date)
        updateSpeed()
        updateSuspicion(delta: delta)
    }

    mutating func refreshDuration(at date: Date) {
        guard inputStartedAt != nil, characterCount > 0 else { return }
        inputEndedAt = date
        updateDuration(at: date)
        updateSpeed()
    }

    private mutating func updateDuration(at date: Date) {
        guard let startedAt = inputStartedAt else {
            inputDurationMs = 0
            return
        }
        inputDurationMs = max(Int(date.timeIntervalSince(startedAt) * 1000), 0)
    }

    private mutating func updateSpeed() {
        let seconds = max(Double(inputDurationMs) / 1000.0, 1.0)
        maxCharsPerSecond = max(maxCharsPerSecond, Double(characterCount) / seconds)
    }

    private mutating func updateSuspicion(delta: Int) {
        guard delta > 0 else { return }

        if delta >= 50 {
            suspiciousBulkInputCount += 1
        }

        if characterCount >= 100 && inputDurationMs < 3_000 {
            suspiciousBulkInputCount += 1
        }

        if characterCount >= 300 && inputDurationMs < 10_000 {
            suspiciousBulkInputCount += 1
        }
    }
}
