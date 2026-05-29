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

        guard let token = try credentialStore.read(account: DeepSeekCredential.tokenAccount),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationWorkflowError.missingToken
        }

        let translatedText = try await translationClient.translate(
            text: trimmedInput,
            source: source,
            target: target,
            apiToken: token
        )
        let record = TranslationRecord(
            sourceText: trimmedInput,
            translatedText: translatedText,
            sourceLanguage: source,
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
