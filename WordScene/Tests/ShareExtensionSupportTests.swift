import Foundation
import XCTest
@testable import WordScene

final class ShareExtensionSupportTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordSceneShareExtensionSupportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSaveAndLoadHandoffRecord() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: true
        )

        try store.save(record)

        XCTAssertEqual(try store.load(id: record.id), record)
    }

    func testConsumePendingOperationsReturnsAndClearsQueuedOperations() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "good morning",
            translatedText: "早上好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )

        try store.appendPendingOperation(.history(record))
        try store.appendPendingOperation(.favorite(record))

        let operations = try store.consumePendingOperations()

        XCTAssertEqual(operations, [.history(record), .favorite(record)])
        XCTAssertEqual(try store.consumePendingOperations(), [])
    }

    func testDeleteHandoffRemovesStoredRecord() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "thanks",
            translatedText: "谢谢",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )

        try store.save(record)
        try store.delete(id: record.id)

        XCTAssertNil(try store.load(id: record.id))
    }
}
