import Foundation

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

                    let result = persistResult(
                        translatedText: latestText,
                        sourceText: trimmedInput,
                        resolvedSource: source,
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
