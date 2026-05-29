import XCTest
@testable import WordScene

final class SettingsImportExportControllerTests: XCTestCase {
    func testPrepareExportUsesLocalMemoryAndConfiguredFileName() throws {
        let suiteName = "SettingsImportExportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = MemoryLibraryStore(defaults: defaults)
        let service = MemoryImportExportService(
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let controller = SettingsImportExportController(memoryStore: store, importExportService: service)
        let item = MemoryItem(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)
        store.save([item])

        let export = try controller.prepareExport()
        let imported = try service.importItems(from: export.data, existingItems: [])

        XCTAssertEqual(export.fileName, "memory-book-export-20270115.json")
        XCTAssertEqual(export.itemCount, 1)
        XCTAssertTrue(export.privacyNotice.contains("不加密"))
        XCTAssertTrue(export.privacyNotice.contains("不包含 API Token"))
        XCTAssertEqual(imported.items, [item])
    }

    func testImportMemoryPersistsMergedItemsAndReportsCounts() throws {
        let suiteName = "SettingsImportExportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = MemoryLibraryStore(defaults: defaults)
        let service = MemoryImportExportService()
        let controller = SettingsImportExportController(memoryStore: store, importExportService: service)
        let oldItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old"
        )
        let replacementItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "new"
        )
        let addedItem = MemoryItem(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)
        store.save([oldItem])
        let data = try service.exportData(items: [replacementItem, addedItem])

        let summary = try controller.importMemory(from: data)

        XCTAssertEqual(summary.importedCount, 2)
        XCTAssertEqual(summary.replacedCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(store.load().count, 2)
        XCTAssertEqual(store.load().first { $0.sourceText == "hello" }?.note, "new")
        XCTAssertTrue(store.load().contains { $0.sourceText == "cat" })
    }
}
