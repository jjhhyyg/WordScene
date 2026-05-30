import XCTest
@testable import WordScene

final class TranslationWorkflowTests: XCTestCase {
    private enum WorkflowTestError: LocalizedError, Equatable {
        case historyWriteFailed

        var errorDescription: String? {
            switch self {
            case .historyWriteFailed:
                return "history write failed"
            }
        }
    }

    private struct StubCredentialStore: CredentialStoring {
        var token: String?

        func save(_ value: String, account: String) throws {}

        func read(account: String) throws -> String? {
            token
        }

        func delete(account: String) throws {}
    }

    private final class StubTranslationClient: TranslationClienting, @unchecked Sendable {
        let translatedText: String
        private(set) var callCount = 0

        init(translatedText: String) {
            self.translatedText = translatedText
        }

        func translate(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) async throws -> String {
            callCount += 1
            XCTAssertEqual(text, "hello world")
            XCTAssertEqual(source, .auto)
            XCTAssertEqual(target, .zh)
            XCTAssertEqual(apiToken, "test-token")
            return translatedText
        }
    }

    private struct FailingHistoryCoreDataStore: CoreDataTranslationHistoryDataStore {
        func loadHistoryRecords() throws -> [TranslationRecord] {
            []
        }

        func replaceHistoryRecords(_ records: [TranslationRecord]) throws {
            throw WorkflowTestError.historyWriteFailed
        }
    }

    func testSuccessfulTranslationWritesRecentHistory() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let historyRepository = TranslationHistoryRepository(coreDataStore: coreDataStore)
        let translationClient = StubTranslationClient(translatedText: "你好，世界。")
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: translationClient,
            historyStore: historyRepository
        )

        let result = try await workflow.translate(
            text: "  hello world  ",
            source: .auto,
            target: .zh,
            currentHistory: []
        )

        XCTAssertEqual(result.translatedText, "你好，世界。")
        XCTAssertNil(result.persistenceWarningMessage)
        XCTAssertEqual(result.record.sourceText, "hello world")
        XCTAssertEqual(result.record.translatedText, "你好，世界。")
        XCTAssertEqual(result.updatedHistory.map(\.sourceText), ["hello world"])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords().map(\.sourceText), ["hello world"])
        XCTAssertEqual(translationClient.callCount, 1)
    }

    func testTranslationStillSucceedsWhenHistoryPersistenceFails() async throws {
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: StubTranslationClient(translatedText: "你好，世界。"),
            historyStore: TranslationHistoryRepository(
                coreDataStore: FailingHistoryCoreDataStore()
            )
        )

        let result = try await workflow.translate(
            text: "hello world",
            source: .auto,
            target: .zh,
            currentHistory: []
        )

        XCTAssertEqual(result.translatedText, "你好，世界。")
        XCTAssertEqual(result.updatedHistory.map(\.sourceText), ["hello world"])
        XCTAssertEqual(
            result.persistenceWarningMessage,
            "译文已生成，但翻译历史保存失败：history write failed"
        )
    }

    func testTranslationTrimsStoredTokenBeforeCallingProvider() async throws {
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "  test-token\n"),
            translationClient: StubTranslationClient(translatedText: "你好，世界。"),
            historyStore: TranslationHistoryRepository(coreDataStore: try CoreDataMemoryStore(inMemory: true))
        )

        let result = try await workflow.translate(
            text: "hello world",
            source: .auto,
            target: .zh,
            currentHistory: []
        )

        XCTAssertEqual(result.translatedText, "你好，世界。")
    }

    func testAutoDetectedSameLanguageCopiesInputWithoutProviderOrToken() async throws {
        try await assertAutoDetectedSameLanguageCopiesInput(
            text: "  我喜欢你  ",
            expectedText: "我喜欢你",
            target: .zh
        )
    }

    func testAutoDetectedEnglishTargetCopiesEnglishInputWithoutProviderOrToken() async throws {
        try await assertAutoDetectedSameLanguageCopiesInput(
            text: "  I like you  ",
            expectedText: "I like you",
            target: .en
        )
    }

    func testAutoDetectedSpanishTargetCopiesSpanishInputWithoutProviderOrToken() async throws {
        try await assertAutoDetectedSameLanguageCopiesInput(
            text: "  Me gusta el café  ",
            expectedText: "Me gusta el café",
            target: .es
        )
    }

    private func assertAutoDetectedSameLanguageCopiesInput(
        text: String,
        expectedText: String,
        target: LanguageSelection
    ) async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let translationClient = StubTranslationClient(translatedText: "不应调用")
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: nil),
            translationClient: translationClient,
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        let result = try await workflow.translate(
            text: text,
            source: .auto,
            target: target,
            currentHistory: []
        )

        XCTAssertEqual(result.translatedText, expectedText)
        XCTAssertEqual(result.record.sourceText, expectedText)
        XCTAssertEqual(result.record.translatedText, expectedText)
        XCTAssertEqual(result.record.sourceLanguage, target)
        XCTAssertEqual(result.record.targetLanguage, target)
        XCTAssertEqual(result.updatedHistory, [result.record])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [result.record])
        XCTAssertEqual(translationClient.callCount, 0)
    }

    func testMissingTokenFailsBeforeCallingProvider() async {
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: nil),
            translationClient: StubTranslationClient(translatedText: "不应调用"),
            historyStore: TranslationHistoryRepository(coreDataStore: try? CoreDataMemoryStore(inMemory: true))
        )

        do {
            _ = try await workflow.translate(
                text: "hello world",
                source: .auto,
                target: .zh,
                currentHistory: []
            )
            XCTFail("Expected missing token to fail before translation.")
        } catch {
            XCTAssertEqual(error as? TranslationWorkflowError, .missingToken)
        }
    }
}
