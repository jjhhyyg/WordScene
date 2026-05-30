import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case translate
    case library
    case history
    case settings

    var id: String { rawValue }

    static var navigationSections: [AppSection] {
        return allCases
    }

    var title: String {
        switch self {
        case .translate: String(localized: "翻译")
        case .library: String(localized: "收藏")
        case .history: String(localized: "翻译历史")
        case .settings: String(localized: "设置")
        }
    }

    var systemImage: String {
        switch self {
        case .translate: "text.bubble"
        case .library: "bookmark"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
