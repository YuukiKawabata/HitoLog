import Foundation

enum HumanBadge: String, Codable {
    case verified
    case checking
    case lowTrust

    var displayText: String {
        switch self {
        case .verified:
            return "本人入力"
        case .checking:
            return "入力確認中"
        case .lowTrust:
            return "信頼度低め"
        }
    }

    var systemImage: String {
        switch self {
        case .verified:
            return "checkmark.seal.fill"
        case .checking:
            return "clock"
        case .lowTrust:
            return "exclamationmark.triangle"
        }
    }
}

