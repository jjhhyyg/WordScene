import Foundation

struct PinyinIndexTerms: Equatable {
    let fullWithSpaces: String
    let fullCompact: String
    let initials: String
}

protocol PinyinTransliterating {
    func indexTerms(for text: String) -> PinyinIndexTerms
}

struct AppleSystemPinyinTransliterator: PinyinTransliterating {
    func indexTerms(for text: String) -> PinyinIndexTerms {
        let transformed = NSMutableString(string: text)
        CFStringTransform(transformed, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(transformed, nil, kCFStringTransformStripDiacritics, false)

        let fullWithSpaces = normalize(String(transformed))
        let fullCompact = fullWithSpaces.replacingOccurrences(of: " ", with: "")
        let initials = fullWithSpaces
            .split(separator: " ")
            .compactMap(\.first)
            .map(String.init)
            .joined()

        return PinyinIndexTerms(
            fullWithSpaces: fullWithSpaces,
            fullCompact: fullCompact,
            initials: initials
        )
    }

    private func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
