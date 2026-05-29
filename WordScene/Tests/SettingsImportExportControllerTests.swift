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

    func testImportMemoryCanKeepExistingDuplicatesAndReportSkippedCount() throws {
        let suiteName = "SettingsImportExportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = MemoryLibraryStore(defaults: defaults)
        let service = MemoryImportExportService()
        let controller = SettingsImportExportController(memoryStore: store, importExportService: service)
        let existingItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "keep me"
        )
        let duplicateItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "incoming"
        )
        let newItem = MemoryItem(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)
        store.save([existingItem])
        let data = try service.exportData(items: [duplicateItem, newItem])

        let summary = try controller.importMemory(from: data, conflictPolicy: .keepExisting)

        XCTAssertEqual(summary.importedCount, 1)
        XCTAssertEqual(summary.replacedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(store.load().count, 2)
        XCTAssertEqual(store.load().first { $0.sourceText == "hello" }?.note, "keep me")
        XCTAssertTrue(store.load().contains { $0.sourceText == "cat" })
    }

    func testImportMemoryRecordsLocalDataChangeAfterSuccessfulSave() throws {
        let suiteName = "SettingsImportExportControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let store = MemoryLibraryStore(defaults: defaults)
        let service = MemoryImportExportService()
        var changeCount = 0
        let controller = SettingsImportExportController(
            memoryStore: store,
            importExportService: service,
            changeRecorder: {
                changeCount += 1
            }
        )
        let item = MemoryItem(sourceText: "offline", translatedText: "离线", sourceLanguage: .en, targetLanguage: .zh)
        let data = try service.exportData(items: [item])

        _ = try controller.importMemory(from: data)

        XCTAssertEqual(changeCount, 1)
    }

    func testImportMemoryDoesNotSaveOrRecordChangeWhenAllIncomingItemsAreSkipped() throws {
        let existingItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "keep me"
        )
        let duplicateItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "incoming"
        )
        let store = SpyMemoryLibraryDataStore(items: [existingItem])
        let service = MemoryImportExportService()
        var changeCount = 0
        let controller = SettingsImportExportController(
            memoryStore: store,
            importExportService: service,
            changeRecorder: {
                changeCount += 1
            }
        )
        let data = try service.exportData(items: [duplicateItem])

        let summary = try controller.importMemory(from: data, conflictPolicy: .keepExisting)

        XCTAssertEqual(summary.importedCount, 0)
        XCTAssertEqual(summary.replacedCount, 0)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.totalCount, 1)
        XCTAssertEqual(summary.statusMessage, "未导入新内容，已跳过 1 条重复项。")
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(store.items, [existingItem])
    }
}

private final class SpyMemoryLibraryDataStore: MemoryLibraryDataStore {
    var items: [MemoryItem]
    private(set) var saveCount = 0

    init(items: [MemoryItem]) {
        self.items = items
    }

    func load() -> [MemoryItem] {
        items
    }

    func save(_ items: [MemoryItem]) {
        saveCount += 1
        self.items = items
    }

    func loadOrThrow() throws -> [MemoryItem] {
        items
    }

    func saveOrThrow(_ items: [MemoryItem]) throws {
        saveCount += 1
        self.items = items
    }
}
