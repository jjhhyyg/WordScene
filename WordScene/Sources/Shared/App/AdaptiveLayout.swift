import SwiftUI

enum AdaptiveLayout: Equatable {
    case compact
    case balanced
    case expanded

    init(availableWidth: CGFloat) {
        if availableWidth < 900 {
            self = .compact
        } else if availableWidth < 1100 {
            self = .balanced
        } else {
            self = .expanded
        }
    }

    var usesTabNavigation: Bool {
        self == .compact
    }

    var usesCompactContent: Bool {
        self == .compact
    }

    var usesContentColumns: Bool {
        self == .expanded
    }

    var sidebarMinWidth: CGFloat {
        self == .balanced ? 132 : 168
    }

    var sidebarIdealWidth: CGFloat {
        self == .balanced ? 148 : 188
    }

    var sidebarMaxWidth: CGFloat {
        self == .balanced ? 168 : 240
    }

    var pageHorizontalPadding: CGFloat {
        switch self {
        case .compact:
            return 18
        case .balanced:
            return 22
        case .expanded:
            return 28
        }
    }

    var pageBottomPadding: CGFloat {
        switch self {
        case .compact:
            return 40
        case .balanced:
            return 42
        case .expanded:
            return 44
        }
    }
}

private struct AdaptiveLayoutKey: EnvironmentKey {
    static let defaultValue: AdaptiveLayout = .expanded
}

extension EnvironmentValues {
    var adaptiveLayout: AdaptiveLayout {
        get { self[AdaptiveLayoutKey.self] }
        set { self[AdaptiveLayoutKey.self] = newValue }
    }
}
