import Foundation

enum ValidationUtil {
    enum HandleValidationResult: Equatable {
        case valid
        case tooShort
        case tooLong
        case reserved
        case invalidCharacters

        var message: String? {
            switch self {
            case .valid:
                return nil
            case .tooShort:
                return "ユーザーIDは3文字以上で入力してください。"
            case .tooLong:
                return "ユーザーIDは20文字以内で入力してください。"
            case .reserved:
                return "このユーザーIDは使用できません。"
            case .invalidCharacters:
                return "ユーザーIDに使えるのは英数字とアンダースコアのみです。"
            }
        }
    }

    static let reservedHandles: Set<String> = [
        "admin",
        "support",
        "help",
        "official",
        "hitolog",
        "api",
        "root"
    ]

    static func isValidHandle(_ handle: String) -> Bool {
        validateHandle(handle) == .valid
    }

    static func validateHandle(_ handle: String) -> HandleValidationResult {
        if handle.count < 3 {
            return .tooShort
        }
        if handle.count > 20 {
            return .tooLong
        }
        if reservedHandles.contains(handle.lowercased()) {
            return .reserved
        }
        if handle.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) == nil {
            return .invalidCharacters
        }
        return .valid
    }
}
