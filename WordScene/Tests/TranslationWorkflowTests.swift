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
        let expectedSource: LanguageSelection
        let expectedTarget: LanguageSelection
        let translatedText: String
        let detectedSourceLanguage: LanguageSelection
        let streamedTexts: [String]
        let streamError: Error?
        private(set) var callCount = 0
        private(set) var streamCallCount = 0

        init(
            expectedText: String = "hello world",
            expectedSource: LanguageSelection = .auto,
            expectedTarget: LanguageSelection = .zh,
            translatedText: String,
            detectedSourceLanguage: LanguageSelection = .en,
            streamedTexts: [String]? = nil,
            streamError: Error? = nil
        ) {
            self.expectedText = expectedText
            self.expectedSource = expectedSource
            self.expectedTarget = expectedTarget
            self.translatedText = translatedText
            self.detectedSourceLanguage = detectedSourceLanguage
            self.streamedTexts = streamedTexts ?? [translatedText]
            self.streamError = streamError
        }

        func translate(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) async throws -> TranslationLLMResult {
            callCount += 1
            XCTAssertEqual(text, expectedText)
            XCTAssertEqual(source, expectedSource)
            XCTAssertEqual(target, expectedTarget)
            XCTAssertEqual(apiToken, "test-token")
            return TranslationLLMResult(
                translatedText: translatedText,
                detectedSourceLanguage: detectedSourceLanguage
            )
        }

        func streamTranslation(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) -> AsyncThrowingStream<TranslationLLMStreamEvent, Error> {
            streamCallCount += 1
            XCTAssertEqual(text, expectedText)
            XCTAssertEqual(source, expectedSource)
            XCTAssertEqual(target, expectedTarget)
            XCTAssertEqual(apiToken, "test-token")

            let streamedTexts = streamedTexts
            let streamError = streamError
            let detectedSourceLanguage = detectedSourceLanguage
            return AsyncThrowingStream { continuation in
                if let streamError {
                    continuation.finish(throwing: streamError)
                    return
                }

                for text in streamedTexts {
                    continuation.yield(.partial(text))
                }
                continuation.yield(.completed(TranslationLLMResult(
                    translatedText: streamedTexts.last ?? "",
                    detectedSourceLanguage: detectedSourceLanguage
                )))
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

    func testAutoSourceTranslationUsesProviderDetectedSourceLanguageInRecord() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let translationClient = StubTranslationClient(
            expectedText: "Hola",
            translatedText: "你好",
            detectedSourceLanguage: .es
        )
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

    func testAutoSourceMixedTextAlwaysCallsProviderEvenWhenTargetIsEnglish() async throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let sourceText = "不过为啥你会预置一个 rebuild database 的指令"
        let translationClient = StubTranslationClient(
            expectedText: sourceText,
            expectedTarget: .en,
            translatedText: "But why would you preset a rebuild database command?",
            detectedSourceLanguage: .zh
        )
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: translationClient,
            historyStore: TranslationHistoryRepository(coreDataStore: coreDataStore)
        )

        let result = try await workflow.translate(
            text: "  \(sourceText)  ",
            source: .auto,
            target: .en,
            currentHistory: []
        )

        XCTAssertEqual(result.translatedText, "But why would you preset a rebuild database command?")
        XCTAssertEqual(result.record.sourceText, sourceText)
        XCTAssertEqual(result.record.sourceLanguage, .zh)
        XCTAssertEqual(result.record.targetLanguage, .en)
        XCTAssertEqual(result.updatedHistory, [result.record])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [result.record])
        XCTAssertEqual(translationClient.callCount, 1)
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
