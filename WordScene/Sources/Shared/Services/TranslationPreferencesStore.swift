import Foundation

struct TranslationPreferencesStore: @unchecked Sendable {
    static let defaultTargetLanguageKey = "translation.defaultTargetLanguage"

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
}

extension UserDefaults {
    static var wordSceneShared: UserDefaults {
        UserDefaults(suiteName: ShareExtensionConfiguration.appGroupIdentifier) ?? .standard
    }
}
