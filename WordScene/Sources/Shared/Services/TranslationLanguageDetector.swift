import Foundation
import NaturalLanguage

enum TranslationLanguageDetector {
    private static let minimumConfidence = 0.35

    static func detect(_ text: String) -> LanguageSelection? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let language = confidentDominantLanguage(from: recognizer),
           let selection = languageSelection(for: language) {
            return selection
        }

        let normalizedText = text.lowercased()

        if containsHanScript(text) {
            return .zh
        }

        if normalizedText.range(of: #"[ñáéíóúü¿¡]"#, options: .regularExpression) != nil {
            return .es
        }

        if normalizedText.range(of: #"[a-z]"#, options: .regularExpression) != nil {
            return .en
        }

        return nil
    }

    private static func confidentDominantLanguage(from recognizer: NLLanguageRecognizer) -> NLLanguage? {
        recognizer.languageHypotheses(withMaximum: 3)
            .sorted { $0.value > $1.value }
            .first { language, confidence in
                confidence >= minimumConfidence && languageSelection(for: language) != nil
            }?
            .key
    }

    private static func languageSelection(for language: NLLanguage) -> LanguageSelection? {
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return .zh
        case .english:
            return .en
        case .spanish:
            return .es
        default:
            return nil
        }
    }

    private static func containsHanScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
                (0x3400...0x4DBF).contains(Int(scalar.value)) ||
                (0x20000...0x2A6DF).contains(Int(scalar.value)) ||
                (0x2A700...0x2B73F).contains(Int(scalar.value)) ||
                (0x2B740...0x2B81F).contains(Int(scalar.value)) ||
                (0x2B820...0x2CEAF).contains(Int(scalar.value)) ||
                (0x2CEB0...0x2EBEF).contains(Int(scalar.value))
        }
    }
}
