import Foundation

struct AppBuildInfo: Equatable {
    let displayName: String
    let version: String
    let build: String

    init(infoDictionary: [String: Any]) {
        displayName = Self.stringValue(
            for: "CFBundleDisplayName",
            in: infoDictionary,
            fallback: Self.stringValue(for: "CFBundleName", in: infoDictionary, fallback: "WordScene")
        )
        version = Self.stringValue(for: "CFBundleShortVersionString", in: infoDictionary, fallback: "1.0.0")
        build = Self.stringValue(for: "CFBundleVersion", in: infoDictionary, fallback: "1")
    }

    static func current(bundle: Bundle = .main) -> AppBuildInfo {
        AppBuildInfo(infoDictionary: bundle.infoDictionary ?? [:])
    }

    var smokeTestDisplayValue: String {
        "\(displayName) \(version) (\(build))"
    }

    private static func stringValue(for key: String, in infoDictionary: [String: Any], fallback: String) -> String {
        guard let value = infoDictionary[key] as? String else {
            return fallback
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
