import Foundation

enum LanguageSelection: String, CaseIterable, Identifiable, Codable {
    case auto
    case zh
    case zhHant = "zh-Hant"
    case en
    case es
    case fr
    case de
    case pt
    case it
    case ru
    case ja
    case ko
    case nl
    case pl
    case ar
    case tr
    case vi
    case indonesian = "id"
    case hi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: String(localized: "自动检测")
        case .zh: String(localized: "简体中文")
        case .zhHant: String(localized: "繁体中文")
        case .en: String(localized: "英文")
        case .es: String(localized: "西班牙语")
        case .fr: String(localized: "法语")
        case .de: String(localized: "德语")
        case .pt: String(localized: "葡萄牙语")
        case .it: String(localized: "意大利语")
        case .ru: String(localized: "俄语")
        case .ja: String(localized: "日语")
        case .ko: String(localized: "韩语")
        case .nl: String(localized: "荷兰语")
        case .pl: String(localized: "波兰语")
        case .ar: String(localized: "阿拉伯语")
        case .tr: String(localized: "土耳其语")
        case .vi: String(localized: "越南语")
        case .indonesian: String(localized: "印尼语")
        case .hi: String(localized: "印地语")
        }
    }

    var translationPromptName: String {
        switch self {
        case .auto: "auto-detect"
        case .zh: "Simplified Chinese"
        case .zhHant: "Traditional Chinese"
        case .en: "English"
        case .es: "Spanish"
        case .fr: "French"
        case .de: "German"
        case .pt: "Portuguese"
        case .it: "Italian"
        case .ru: "Russian"
        case .ja: "Japanese"
        case .ko: "Korean"
        case .nl: "Dutch"
        case .pl: "Polish"
        case .ar: "Arabic"
        case .tr: "Turkish"
        case .vi: "Vietnamese"
        case .indonesian: "Indonesian"
        case .hi: "Hindi"
        }
    }

    var searchAliases: [String] {
        switch self {
        case .auto:
            ["自动检测", "Auto Detect", "Detección automática", "自动", rawValue]
        case .zh:
            ["中文", "简体中文", "Simplified Chinese", "Chinese", "Chino", rawValue]
        case .zhHant:
            ["繁体中文", "繁體中文", "Traditional Chinese", rawValue]
        case .en:
            ["英文", "English", "Inglés", rawValue]
        case .es:
            ["西班牙语", "Spanish", "Español", rawValue]
        case .fr:
            ["法语", "French", "Français", rawValue]
        case .de:
            ["德语", "German", "Deutsch", rawValue]
        case .pt:
            ["葡萄牙语", "Portuguese", "Português", rawValue]
        case .it:
            ["意大利语", "Italian", "Italiano", rawValue]
        case .ru:
            ["俄语", "Russian", "Русский", rawValue]
        case .ja:
            ["日语", "Japanese", "日本語", rawValue]
        case .ko:
            ["韩语", "Korean", "한국어", rawValue]
        case .nl:
            ["荷兰语", "Dutch", "Nederlands", rawValue]
        case .pl:
            ["波兰语", "Polish", "Polski", rawValue]
        case .ar:
            ["阿拉伯语", "Arabic", "العربية", rawValue]
        case .tr:
            ["土耳其语", "Turkish", "Türkçe", rawValue]
        case .vi:
            ["越南语", "Vietnamese", "Tiếng Việt", rawValue]
        case .indonesian:
            ["印尼语", "印度尼西亚语", "Indonesian", "Bahasa Indonesia", rawValue]
        case .hi:
            ["印地语", "Hindi", "हिन्दी", rawValue]
        }
    }

    static var translationTargets: [LanguageSelection] {
        [
            .zh,
            .zhHant,
            .en,
            .es,
            .fr,
            .de,
            .pt,
            .it,
            .ru,
            .ja,
            .ko,
            .nl,
            .pl,
            .ar,
            .tr,
            .vi,
            .indonesian,
            .hi
        ]
    }

    static var sourceOptions: [LanguageSelection] {
        [.auto] + translationTargets
    }

    static func targetOptions(excluding source: LanguageSelection) -> [LanguageSelection] {
        let targets = translationTargets
        guard source != .auto else { return targets }
        return targets.filter { $0 != source }
    }
}
