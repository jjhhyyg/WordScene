import XCTest
@testable import WordScene

final class MemoryImportExportServiceTests: XCTestCase {
    func testExportsAndImportsMemoryItemsWithoutToken() throws {
        let service = MemoryImportExportService(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            appVersion: "1.0.0",
            appBuild: "1",
            platform: "TestOS"
        )
        let item = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting"
        )

        let data = try service.exportData(items: [item])
        let exportedText = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(exportedText.contains("\"export_schema_version\" : \"2.0\""))
        XCTAssertTrue(exportedText.contains("\"checksum\" : \"sha256:"))
        XCTAssertFalse(exportedText.contains("TEST_TOKEN_SHOULD_NOT_EXPORT"))

        let imported = try service.importItems(from: data, existingItems: [], conflictStrategy: .replaceDuplicates)

        XCTAssertEqual(imported.items, [item])
        XCTAssertEqual(imported.importedCount, 1)
        XCTAssertEqual(imported.replacedCount, 0)
        XCTAssertEqual(imported.skippedCount, 0)
    }

    func testImportRejectsTamperedChecksum() throws {
        let service = MemoryImportExportService()
        let item = MemoryItem(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)
        var exportedText = String(decoding: try service.exportData(items: [item]), as: UTF8.self)
        exportedText = exportedText.replacingOccurrences(of: "cat", with: "dog")

        XCTAssertThrowsError(try service.importItems(from: Data(exportedText.utf8), existingItems: [])) { error in
            XCTAssertEqual(error as? MemoryImportExportError, .checksumMismatch)
        }
    }

    func testImportCanReplaceDuplicateItems() throws {
        let service = MemoryImportExportService()
        let oldItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old"
        )
        let newItem = MemoryItem(
            sourceText: " hello ",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "new"
        )
        let data = try service.exportData(items: [newItem])

        let imported = try service.importItems(from: data, existingItems: [oldItem], conflictStrategy: .replaceDuplicates)

        XCTAssertEqual(imported.items.count, 1)
        XCTAssertEqual(imported.items.first?.note, "new")
        XCTAssertEqual(imported.importedCount, 1)
        XCTAssertEqual(imported.replacedCount, 1)
        XCTAssertEqual(imported.skippedCount, 0)
    }

    func testImportCanSkipDuplicateItems() throws {
        let service = MemoryImportExportService()
        let oldItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old"
        )
        let newItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "new"
        )
        let data = try service.exportData(items: [newItem])

        let imported = try service.importItems(from: data, existingItems: [oldItem], conflictStrategy: .skipDuplicates)

        XCTAssertEqual(imported.items.count, 1)
        XCTAssertEqual(imported.items.first?.note, "old")
        XCTAssertEqual(imported.importedCount, 0)
        XCTAssertEqual(imported.replacedCount, 0)
        XCTAssertEqual(imported.skippedCount, 1)
    }

    func testExportFileNameUsesConfiguredDateFormat() {
        let service = MemoryImportExportService(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(service.exportFileName(), "memory-book-export-20270115.json")
    }
}
