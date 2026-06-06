import Foundation

struct TranslationPreferencesStore: @unchecked Sendable {
    static let defaultTargetLanguageKey = "translation.defaultTargetLanguage"
    static let shareSourceLanguageKey = "translation.share.sourceLanguage"
    static let shareTargetLanguageKey = "translation.share.targetLanguage"
    static let shareAutoTranslateEnabledKey = "translation.share.autoTranslateEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .wordSceneShared) {
        self.defaults = defaults
    }

    var defaultTargetLanguage: LanguageSelection {
        get {
            guard let rawValue = defaults.string(forKey: Self.defaultTargetLanguageKey),
                  let language = LanguageSelection(rawValue: rawValue),
                  LanguageSelection.translationTargets.contains(language) else {
                return .zh
            }

            return language
        }
        nonmutating set {
            let target = LanguageSelection.translationTargets.contains(newValue) ? newValue : .zh
            defaults.set(target.rawValue, forKey: Self.defaultTargetLanguageKey)
        }
    }

    var shareSourceLanguage: LanguageSelection {
        get {
            guard let rawValue = defaults.string(forKey: Self.shareSourceLanguageKey),
                  let language = LanguageSelection(rawValue: rawValue),
                  LanguageSelection.sourceOptions.contains(language) else {
                return .auto
            }

            return language
        }
        nonmutating set {
            let source = LanguageSelection.sourceOptions.contains(newValue) ? newValue : .auto
            defaults.set(source.rawValue, forKey: Self.shareSourceLanguageKey)
            normalizeShareLanguageDirection()
        }
    }

    var shareTargetLanguage: LanguageSelection {
        get {
            guard let rawValue = defaults.string(forKey: Self.shareTargetLanguageKey),
                  let language = LanguageSelection(rawValue: rawValue),
                  LanguageSelection.translationTargets.contains(language) else {
                return .zh
            }

            let source = shareSourceLanguage
            if source != .auto, language == source {
                return .zh
            }

            return language
        }
        nonmutating set {
            let target = LanguageSelection.translationTargets.contains(newValue) ? newValue : .zh
            defaults.set(target.rawValue, forKey: Self.shareTargetLanguageKey)
            normalizeShareLanguageDirection()
        }
    }

    var isShareAutoTranslateEnabled: Bool {
        get {
            defaults.bool(forKey: Self.shareAutoTranslateEnabledKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: Self.shareAutoTranslateEnabledKey)
        }
    }

    private func normalizeShareLanguageDirection() {
        let source = shareSourceLanguage
        let target = shareTargetLanguage
        let normalizedTarget = LanguageSelection.targetOptions(excluding: source).contains(target)
            ? target
            : Self.defaultShareTarget(excluding: source)
        defaults.set(source.rawValue, forKey: Self.shareSourceLanguageKey)
        defaults.set(normalizedTarget.rawValue, forKey: Self.shareTargetLanguageKey)
    }

    private static func defaultShareTarget(excluding source: LanguageSelection) -> LanguageSelection {
        let targets = LanguageSelection.targetOptions(excluding: source)
        return targets.first { $0 == .zh } ?? targets.first ?? .zh
    }
}

extension UserDefaults {
    static var wordSceneShared: UserDefaults {
        UserDefaults(suiteName: ShareExtensionConfiguration.appGroupIdentifier) ?? .standard
    }
}
