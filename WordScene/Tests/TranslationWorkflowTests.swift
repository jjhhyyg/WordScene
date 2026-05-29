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

    private struct StubTranslationClient: TranslationClienting {
        let translatedText: String

        func translate(
            text: String,
            source: LanguageSelection,
            target: LanguageSelection,
            apiToken: String
        ) async throws -> String {
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
        let workflow = TranslationWorkflow(
            credentialStore: StubCredentialStore(token: "test-token"),
            translationClient: StubTranslationClient(translatedText: "你好，世界。"),
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
