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
        let expectedText: String
        let translatedText: String
        let streamedTexts: [String]
        let streamError: Error?
        private(set) var callCount = 0
        private(set) var streamCallCount = 0

        init(
            expectedText: String = "hello world",
            translatedText: String,
            streamedTexts: [String]? = nil,
            streamError: Error? = nil
        ) {
            self.expectedText = expectedText
            self.translatedText = translatedText
            self.streamedTexts = streamedTexts ?? [translatedText]
            self.streamError = streamError
        }

        func translate(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) async throws -> String {
            callCount += 1
            XCTAssertEqual(text, expectedText)
            XCTAssertEqual(source, .auto)
            XCTAssertEqual(target, .zh)
            XCTAssertEqual(apiToken, "test-token")
            return translatedText
        }

        func streamTranslation(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) -> AsyncThrowingStream<String, Error> {
            streamCallCount += 1
            XCTAssertEqual(text, expectedText)
            XCTAssertEqual(source, .auto)
            XCTAssertEqual(target, .zh)
            XCTAssertEqual(apiToken, "test-token")

            let streamedTexts = streamedTexts
            let streamError = streamError
            return AsyncThrowingStream { continuation in
                if let streamError {
                    continuation.finish(throwing: streamError)
                    return
                }

                for text in streamedTexts {
                    continuation.yield(text)
                }
                continuation.finish()
            }
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
        XCTAssertEqual(result.record.sourceLanguage, .en)
        XCTAssertEqual(result.record.targetLanguage, .zh)
        XCTAssertEqual(result.updatedHistory.map(\.sourceText), ["hello world"])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords().map(\.sourceText), ["hello world"])
        XCTAssertEqual(translationClient.callCount, 1)
    }

    func testAutoDetectedSpanishTranslationWritesDetectedSourceLanguage() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let translationClient = StubTranslationClient(expectedText: "Hola", translatedText: "你好")
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: translationClient,
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        let result = try await workflow.translate(
            text: "Hola",
            source: .auto,
            target: .zh,
            currentHistory: []
        )

        XCTAssertEqual(result.record.sourceLanguage, .es)
        XCTAssertEqual(result.record.targetLanguage, .zh)
        XCTAssertEqual(MemoryItem(record: result.record).sourceLanguage, .es)
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
        let warningFormat = String(localized: "译文已生成，但翻译历史保存失败：%@", comment: "Warning shown when translation succeeds but history cannot be saved. The placeholder is the system error description.")
        XCTAssertEqual(
            result.persistenceWarningMessage,
            String(format: warningFormat, "history write failed")
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

    func testStreamTranslationYieldsPartialsThenCompletedResultAndPersistsHistory() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let translationClient = StubTranslationClient(
            translatedText: "final unused",
            streamedTexts: ["你", "你好，世界。"]
        )
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: translationClient,
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        let events = try await collectStreamEvents(
            workflow.streamTranslation(
                text: "  hello world  ",
                source: .auto,
                target: .zh,
                currentHistory: []
            )
        )

        XCTAssertEqual(events.map(\.partialText), ["你", "你好，世界。", nil])
        guard case .completed(let result) = events.last else {
            return XCTFail("Expected completed stream event.")
        }
        XCTAssertEqual(result.translatedText, "你好，世界。")
        XCTAssertEqual(result.record.sourceText, "hello world")
        XCTAssertEqual(result.record.sourceLanguage, .en)
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [result.record])
        XCTAssertEqual(translationClient.streamCallCount, 1)
        XCTAssertEqual(translationClient.callCount, 0)
    }

    func testStreamTranslationEmptyProviderOutputFailsWithoutPersistingHistory() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: StubTranslationClient(translatedText: "", streamedTexts: ["  "]),
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        do {
            _ = try await collectStreamEvents(
                workflow.streamTranslation(
                    text: "hello world",
                    source: .auto,
                    target: .zh,
                    currentHistory: []
                )
            )
            XCTFail("Expected empty streamed output to fail.")
        } catch {
            XCTAssertEqual(error as? DeepSeekTranslationError, .emptyOutput)
            XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [])
        }
    }

    func testStreamTranslationPropagatesTimeoutWithoutPersistingHistory() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: StubTranslationClient(
                translatedText: "unused",
                streamError: DeepSeekTranslationError.timedOut
            ),
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        do {
            _ = try await collectStreamEvents(
                workflow.streamTranslation(
                    text: "hello world",
                    source: .auto,
                    target: .zh,
                    currentHistory: []
                )
            )
            XCTFail("Expected streamed timeout to fail.")
        } catch {
            XCTAssertEqual(error as? DeepSeekTranslationError, .timedOut)
            XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [])
        }
    }

    private func collectStreamEvents(
        _ stream: AsyncThrowingStream<TranslationWorkflowStreamEvent, Error>
    ) async throws -> [TranslationWorkflowStreamEvent] {
        var events: [TranslationWorkflowStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }
}

private extension TranslationWorkflowStreamEvent {
    var partialText: String? {
        guard case .partial(let text) = self else {
            return nil
        }
        return text
    }
}
