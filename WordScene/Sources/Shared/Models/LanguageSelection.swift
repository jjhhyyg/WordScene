import Foundation

enum LanguageSelection: String, CaseIterable, Identifiable, Codable {
    case auto
    case zh
    case en
    case es

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "自动检测")
        case .zh: String(localized: "中文")
        case .en: String(localized: "英文")
        case .es: String(localized: "西班牙语")
        }
    }

    var translationPromptName: String {
        switch self {
        case .auto: "auto-detect"
        case .zh: "Chinese"
        case .en: "English"
        case .es: "Spanish"
        }
    }

    var searchAliases: [String] {
        switch self {
        case .auto:
            ["自动检测", "Auto Detect", "Detección automática", rawValue]
        case .zh:
            ["中文", "Chinese", "Chino", rawValue]
        case .en:
            ["英文", "English", "Inglés", rawValue]
        case .es:
            ["西班牙语", "Spanish", "Español", rawValue]
        }
    }

    static var sourceOptions: [LanguageSelection] {
        [.auto, .zh, .en, .es]
    }

    static func targetOptions(excluding source: LanguageSelection) -> [LanguageSelection] {
        let targets: [LanguageSelection] = [.zh, .en, .es]
        guard source != .auto else { return targets }
        return targets.filter { $0 != source }
    }
}
