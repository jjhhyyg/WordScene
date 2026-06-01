import Foundation

struct TranslationLanguageDirection: Equatable {
    var source: LanguageSelection
    var target: LanguageSelection

    var canSwap: Bool {
        source != .auto
    }

    func swapped() -> TranslationLanguageDirection {
        guard canSwap else {
            return self
        }

        if LanguageSelection.targetOptions(excluding: target).contains(source) {
            return TranslationLanguageDirection(source: target, target: source)
        }

        return TranslationLanguageDirection(
            source: target,
            target: Self.defaultTarget(excluding: target)
        )
    }

    func normalized() -> TranslationLanguageDirection {
        guard LanguageSelection.targetOptions(excluding: source).contains(target) else {
            return TranslationLanguageDirection(
                source: source,
                target: Self.defaultTarget(excluding: source)
            )
        }

        return self
    }

    private static func defaultTarget(excluding source: LanguageSelection) -> LanguageSelection {
        LanguageSelection.targetOptions(excluding: source).first ?? .zh
    }
}
