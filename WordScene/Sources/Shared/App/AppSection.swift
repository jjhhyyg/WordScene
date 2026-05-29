import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case translate
    case library
    case search
    case settings

    var id: String { rawValue }

    static var navigationSections: [AppSection] {
        #if os(macOS)
        return [.translate, .library, .search]
        #else
        return allCases
        #endif
    }

    var title: String {
        switch self {
        case .translate: "翻译"
        case .library: "收藏"
        case .search: "搜索"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: "text.bubble"
        case .library: "bookmark"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}
