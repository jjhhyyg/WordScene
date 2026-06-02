import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    static let storageKey = "app.theme"

    case auto
    case light
    case dark
    case black
    case mistBlue
    case sage
    case lavender
    case silver
    case cosmicOrange

    var id: String { rawValue }

    var displayNameLocalizationKey: String {
        switch self {
        case .auto:
            return "Auto"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .black:
            return "Black"
        case .mistBlue:
            return "Mist Blue"
        case .sage:
            return "Sage"
        case .lavender:
            return "Lavender"
        case .silver:
            return "Silver"
        case .cosmicOrange:
            return "Cosmic Orange"
        }
    }

    var displayName: String {
        switch self {
        case .auto:
            return String(localized: "Auto", comment: "Theme option display name.")
        case .light:
            return String(localized: "Light", comment: "Theme option display name.")
        case .dark:
            return String(localized: "Dark", comment: "Theme option display name.")
        case .black:
            return String(localized: "Black", comment: "Theme option display name.")
        case .mistBlue:
            return String(localized: "Mist Blue", comment: "Theme option display name.")
        case .sage:
            return String(localized: "Sage", comment: "Theme option display name.")
        case .lavender:
            return String(localized: "Lavender", comment: "Theme option display name.")
        case .silver:
            return String(localized: "Silver", comment: "Theme option display name.")
        case .cosmicOrange:
            return String(localized: "Cosmic Orange", comment: "Theme option display name.")
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .auto:
            return nil
        case .light, .black, .mistBlue, .sage, .lavender, .silver, .cosmicOrange:
            return .light
        case .dark:
            return .dark
        }
    }

    var palette: AppThemePalette {
        switch self {
        case .auto, .light, .dark:
            return .system
        case .black:
            return .iphoneBlack
        case .mistBlue:
            return .iphoneMistBlue
        case .sage:
            return .iphoneSage
        case .lavender:
            return .iphoneLavender
        case .silver:
            return .iphoneSilver
        case .cosmicOrange:
            return .iphoneCosmicOrange
        }
    }

    static func fromStorageValue(_ value: String) -> AppTheme {
        if value == "blue" || value == "deepBlue" || value == "white" {
            return .auto
        }
        return AppTheme(rawValue: value) ?? .auto
    }
}

struct AppThemePalette: Equatable {
    let primaryHex: String
    let surfaceHex: String
    let backgroundHex: String
    let sidebarHex: String

    static let system = AppThemePalette(
        primaryHex: "#0A84FF",
        surfaceHex: "#F2F2F7",
        backgroundHex: "#F2F2F7",
        sidebarHex: "#F2F2F7"
    )
    static let iphoneBlack = AppThemePalette(
        primaryHex: "#1D1D1F",
        surfaceHex: "#F7F5F0",
        backgroundHex: "#EDEFF3",
        sidebarHex: "#DDE2EA"
    )
    static let iphoneMistBlue = AppThemePalette(
        primaryHex: "#386A8C",
        surfaceHex: "#F8FBFD",
        backgroundHex: "#EAF3FA",
        sidebarHex: "#D9EAF6"
    )
    static let iphoneSage = AppThemePalette(
        primaryHex: "#62785F",
        surfaceHex: "#F8FAF3",
        backgroundHex: "#EAF0E4",
        sidebarHex: "#DCE8D6"
    )
    static let iphoneLavender = AppThemePalette(
        primaryHex: "#8167A8",
        surfaceHex: "#FCF9FF",
        backgroundHex: "#F0E9FA",
        sidebarHex: "#E7DCF5"
    )
    static let iphoneSilver = AppThemePalette(
        primaryHex: "#717780",
        surfaceHex: "#FFFFFF",
        backgroundHex: "#EEF0F3",
        sidebarHex: "#E0E4E9"
    )
    static let iphoneCosmicOrange = AppThemePalette(
        primaryHex: "#D85E24",
        surfaceHex: "#FFF8F2",
        backgroundHex: "#FBE7D8",
        sidebarHex: "#F7D3BE"
    )

    var usesCustomPalette: Bool {
        self != .system
    }

    var primary: Color {
        Color(hex: primaryHex)
    }

    var surface: Color {
        Color(hex: surfaceHex)
    }

    var background: Color {
        Color(hex: backgroundHex)
    }

    var sidebar: Color {
        Color(hex: sidebarHex)
    }
}

private struct AppThemePaletteKey: EnvironmentKey {
    static let defaultValue = AppThemePalette.system
}

extension EnvironmentValues {
    var appThemePalette: AppThemePalette {
        get { self[AppThemePaletteKey.self] }
        set { self[AppThemePaletteKey.self] = newValue }
    }
}

extension View {
    func wordSceneTheme(_ theme: AppTheme) -> some View {
        preferredColorScheme(theme.preferredColorScheme)
            .tint(theme.palette.primary)
            .environment(\.appThemePalette, theme.palette)
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)

        let red = Double((integer >> 16) & 0xFF) / 255
        let green = Double((integer >> 8) & 0xFF) / 255
        let blue = Double(integer & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}
