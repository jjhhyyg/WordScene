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

    func testAppendPendingOperationWritesSeparateFilesAndConsumeClearsThem() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let firstRecord = ShareExtensionHandoffRecord(
            sourceText: "first",
            translatedText: "第一个",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )
        let secondRecord = ShareExtensionHandoffRecord(
            sourceText: "second",
            translatedText: "第二个",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: true
        )

        try store.appendPendingOperation(.history(firstRecord))
        try store.appendPendingOperation(.favorite(secondRecord))

        XCTAssertEqual(try pendingOperationFileNames().count, 2)
        XCTAssertFalse(fileExists(named: "share-pending-operations.json"))

        let operations = try store.consumePendingOperations()

        XCTAssertEqual(operations, [.history(firstRecord), .favorite(secondRecord)])
        XCTAssertEqual(try pendingOperationFileNames(), [])
    }

    func testConsumePendingOperationsDeletesCorruptFilesAndReturnsValidOperations() throws {
        let store = ShareExtensionHandoffStore(directoryURL: temporaryDirectory)
        let record = ShareExtensionHandoffRecord(
            sourceText: "valid",
            translatedText: "有效",
            sourceLanguage: .en,
            targetLanguage: .zh,
            isFavoritePending: false
        )
        let corruptFileURL = temporaryDirectory.appendingPathComponent(
            "share-pending-operation-00000000-0000-0000-0000-000000000000.json"
        )
        try Data("{not json".utf8).write(to: corruptFileURL, options: .atomic)

        try store.appendPendingOperation(.history(record))

        let operations = try store.consumePendingOperations()

        XCTAssertEqual(operations, [.history(record)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptFileURL.path))
        XCTAssertEqual(try pendingOperationFileNames(), [])
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

    private func pendingOperationFileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )
        .map(\.lastPathComponent)
        .filter { $0.hasPrefix("share-pending-operation-") && $0.hasSuffix(".json") }
        .sorted()
    }

    private func fileExists(named fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(fileName).path)
    }
}
