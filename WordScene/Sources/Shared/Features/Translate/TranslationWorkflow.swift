import Foundation
import NaturalLanguage

enum TranslationWorkflowError: Error, Equatable {
    case missingToken
}

struct TranslationWorkflowResult: Equatable {
    let translatedText: String
    let record: TranslationRecord
    let updatedHistory: [TranslationRecord]
    let persistenceWarningMessage: String?
}

struct TranslationWorkflow {
    let credentialStore: any CredentialStoring
    let translationClient: any TranslationClienting
    let historyStore: TranslationHistoryRepository

    init(
        credentialStore: any CredentialStoring = KeychainCredentialStore(),
        translationClient: any TranslationClienting = DeepSeekTranslationClient(),
        historyStore: TranslationHistoryRepository
    ) {
        self.credentialStore = credentialStore
        self.translationClient = translationClient
        self.historyStore = historyStore
    }

    @MainActor
    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        currentHistory: [TranslationRecord]
    ) async throws -> TranslationWorkflowResult {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw DeepSeekTranslationError.emptyInput
        }

        if source == .auto,
           let detectedSource = TranslationLanguageDetector.detect(trimmedInput),
           detectedSource == target {
            return persistResult(
                translatedText: trimmedInput,
                sourceText: trimmedInput,
                resolvedSource: detectedSource,
                target: target,
                currentHistory: currentHistory
            )
        }

        guard let rawToken = try credentialStore.read(account: DeepSeekCredential.tokenAccount) else {
            throw TranslationWorkflowError.missingToken
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw TranslationWorkflowError.missingToken
        }

        let translatedText = try await translationClient.translate(
            text: trimmedInput,
            source: source,
            target: target,
            apiToken: token
        )

        return persistResult(
            translatedText: translatedText,
            sourceText: trimmedInput,
            resolvedSource: source,
            target: target,
            currentHistory: currentHistory
        )
    }

    private func persistResult(
        translatedText: String,
        sourceText: String,
        resolvedSource: LanguageSelection,
        target: LanguageSelection,
        currentHistory: [TranslationRecord]
    ) -> TranslationWorkflowResult {
        let record = TranslationRecord(
            sourceText: sourceText,
            translatedText: translatedText,
            sourceLanguage: resolvedSource,
            targetLanguage: target
        )
        let updatedHistory = historyStore.adding(record, to: currentHistory)
        let warningMessage: String?

        do {
            try historyStore.saveOrThrow(updatedHistory)
            warningMessage = nil
        } catch {
            warningMessage = "译文已生成，但翻译历史保存失败：\(error.localizedDescription)"
        }

        return TranslationWorkflowResult(
            translatedText: translatedText,
            record: record,
            updatedHistory: updatedHistory,
            persistenceWarningMessage: warningMessage
        )
    }
}

private enum TranslationLanguageDetector {
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
