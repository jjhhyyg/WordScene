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

enum TranslationWorkflowStreamEvent: Equatable {
    case partial(String)
    case completed(TranslationWorkflowResult)
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
        let resolvedSource = source == .auto
            ? TranslationLanguageDetector.detect(trimmedInput) ?? source
            : source

        return persistResult(
            translatedText: translatedText,
            sourceText: trimmedInput,
            resolvedSource: resolvedSource,
            target: target,
            currentHistory: currentHistory
        )
    }

    @MainActor
    func streamTranslation(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        currentHistory: [TranslationRecord]
    ) -> AsyncThrowingStream<TranslationWorkflowStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let credentialStore = credentialStore
            let translationClient = translationClient

            let task = Task { @MainActor in
                do {
                    let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedInput.isEmpty else {
                        throw DeepSeekTranslationError.emptyInput
                    }

                    if source == .auto,
                       let detectedSource = TranslationLanguageDetector.detect(trimmedInput),
                       detectedSource == target {
                        let result = persistResult(
                            translatedText: trimmedInput,
                            sourceText: trimmedInput,
                            resolvedSource: detectedSource,
                            target: target,
                            currentHistory: currentHistory
                        )
                        continuation.yield(.partial(trimmedInput))
                        continuation.yield(.completed(result))
                        continuation.finish()
                        return
                    }

                    guard let rawToken = try credentialStore.read(account: DeepSeekCredential.tokenAccount) else {
                        throw TranslationWorkflowError.missingToken
                    }
                    let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else {
                        throw TranslationWorkflowError.missingToken
                    }

                    var latestText = ""
                    for try await partialText in translationClient.streamTranslation(
                        text: trimmedInput,
                        source: source,
                        target: target,
                        apiToken: token
                    ) {
                        latestText = partialText
                        continuation.yield(.partial(partialText))
                    }

                    guard !latestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw DeepSeekTranslationError.emptyOutput
                    }

                    let resolvedSource = source == .auto
                        ? TranslationLanguageDetector.detect(trimmedInput) ?? source
                        : source
                    let result = persistResult(
                        translatedText: latestText,
                        sourceText: trimmedInput,
                        resolvedSource: resolvedSource,
                        target: target,
                        currentHistory: currentHistory
                    )
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
            warningMessage = String(
                format: String(localized: "译文已生成，但翻译历史保存失败：%@", comment: "Warning shown when translation succeeds but history cannot be saved. The placeholder is the system error description."),
                error.localizedDescription
            )
        }

        return TranslationWorkflowResult(
            translatedText: translatedText,
            record: record,
            updatedHistory: updatedHistory,
            persistenceWarningMessage: warningMessage
        )
    }
}

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
