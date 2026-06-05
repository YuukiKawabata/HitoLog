import Foundation

struct TypingMetrics: Equatable, Codable {
    /// アイドルとみなす入力間隔のしきい値。これを超える間（考え込み・離席・アプリ閉鎖）は
    /// 入力時間に加算しない。「本当に書いている時間」だけを積み上げるための基準。
    static let idleThresholdMs = 5_000

    private(set) var inputStartedAt: Date?
    /// 直近のキーストローク時刻。次の入力との間隔を測るために使う。
    private(set) var lastInputAt: Date?
    /// 実際に書いていた時間の積算（アクティブ入力時間）。これが入力時間の真実。
    private(set) var activeInputMs = 0
    private(set) var inputDurationMs = 0
    private(set) var characterCount = 0
    private(set) var editCount = 0
    private(set) var deleteCount = 0
    private(set) var maxCharsPerSecond = 0.0
    private(set) var suspiciousBulkInputCount = 0

    init() {}

    var durationText: String {
        let seconds = inputDurationMs / 1000
        return "\(seconds)秒"
    }

    mutating func recordChange(from oldText: String, to newText: String, at date: Date) {
        if inputStartedAt == nil, !newText.isEmpty {
            inputStartedAt = date
        }

        // 直近の入力からの間隔を、しきい値以内のときだけアクティブ入力時間に加算する。
        // 放置やアプリ閉鎖を挟むと間隔がしきい値を超えるため、その分は加算されない。
        if let lastInputAt {
            let gapMs = date.timeIntervalSince(lastInputAt) * 1000
            if gapMs > 0 && gapMs <= Double(Self.idleThresholdMs) {
                activeInputMs += Int(gapMs)
            }
        }
        lastInputAt = date

        characterCount = newText.count

        let delta = newText.count - oldText.count
        if delta > 0 {
            editCount += 1
        } else if delta < 0 {
            deleteCount += 1
        }

        inputDurationMs = activeInputMs
        updateSpeed()
        updateSuspicion(delta: delta)
    }

    /// タイマーから定期的に呼ばれ、現在進行中の打鍵区間だけを暫定的に表示へ反映する。
    /// 直近の入力からしきい値を超えて経過していれば（手が止まっていれば）何も足さない。
    mutating func refreshDuration(at date: Date) {
        guard let lastInputAt, characterCount > 0 else { return }
        let gapMs = date.timeIntervalSince(lastInputAt) * 1000
        let pendingMs = (gapMs > 0 && gapMs <= Double(Self.idleThresholdMs)) ? Int(gapMs) : 0
        inputDurationMs = activeInputMs + pendingMs
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

    // MARK: - Codable（旧下書きとの後方互換）

    private enum CodingKeys: String, CodingKey {
        case inputStartedAt
        case lastInputAt
        case activeInputMs
        case inputDurationMs
        case characterCount
        case editCount
        case deleteCount
        case maxCharsPerSecond
        case suspiciousBulkInputCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputStartedAt = try container.decodeIfPresent(Date.self, forKey: .inputStartedAt)
        lastInputAt = try container.decodeIfPresent(Date.self, forKey: .lastInputAt)
        inputDurationMs = try container.decodeIfPresent(Int.self, forKey: .inputDurationMs) ?? 0
        // activeInputMs が無い旧下書きは、当時の inputDurationMs を引き継ぐ。
        activeInputMs = try container.decodeIfPresent(Int.self, forKey: .activeInputMs) ?? inputDurationMs
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 0
        editCount = try container.decodeIfPresent(Int.self, forKey: .editCount) ?? 0
        deleteCount = try container.decodeIfPresent(Int.self, forKey: .deleteCount) ?? 0
        maxCharsPerSecond = try container.decodeIfPresent(Double.self, forKey: .maxCharsPerSecond) ?? 0
        suspiciousBulkInputCount = try container.decodeIfPresent(Int.self, forKey: .suspiciousBulkInputCount) ?? 0
    }
}
