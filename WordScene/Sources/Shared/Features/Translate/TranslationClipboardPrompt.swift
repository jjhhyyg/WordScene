import Foundation

struct TranslationClipboardPrompt: Equatable {
    struct Acceptance: Equatable {
        let inputText: String
        let sourceLanguage: LanguageSelection
        let targetLanguage: LanguageSelection
    }

    let text: String

    static func make(
        clipboardText: String?,
        currentInput: String,
        dismissedText: String?
    ) -> TranslationClipboardPrompt? {
        guard let clipboardText else {
            return nil
        }

        let normalizedClipboard = normalized(clipboardText)
        guard !normalizedClipboard.isEmpty else {
            return nil
        }

        if normalizedClipboard == normalized(currentInput) {
            return nil
        }

        if normalizedClipboard == dismissedText.map(normalized) {
            return nil
        }

        return TranslationClipboardPrompt(text: normalizedClipboard)
    }

    func acceptance(
        currentSourceLanguage: LanguageSelection,
        currentTargetLanguage: LanguageSelection
    ) -> Acceptance {
        let direction = TranslationLanguageDirection(
            source: currentSourceLanguage,
            target: currentTargetLanguage
        ).normalized()
        return Acceptance(
            inputText: text,
            sourceLanguage: direction.source,
            targetLanguage: direction.target
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
