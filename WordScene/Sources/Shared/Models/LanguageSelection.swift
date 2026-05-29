import Foundation

enum LanguageSelection: String, CaseIterable, Identifiable, Codable {
    case auto
    case zh
    case en
    case es

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "自动检测"
        case .zh: "中文"
        case .en: "英文"
        case .es: "西班牙语"
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

    static var sourceOptions: [LanguageSelection] {
        [.auto, .zh, .en, .es]
    }

    static func targetOptions(excluding source: LanguageSelection) -> [LanguageSelection] {
        let targets: [LanguageSelection] = [.zh, .en, .es]
        guard source != .auto else { return targets }
        return targets.filter { $0 != source }
    }
}
