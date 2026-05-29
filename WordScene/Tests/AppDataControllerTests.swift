import XCTest
@testable import WordScene

final class AppDataControllerTests: XCTestCase {
    func testRepositoriesShareInjectedCoreDataStore() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(coreDataStore: coreDataStore)
        let memoryItem = MemoryItem(
            sourceText: "shared",
            translatedText: "共享",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let historyRecord = TranslationRecord(
            sourceText: "history",
            translatedText: "历史",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        controller.memoryLibrary.save([memoryItem])
        controller.translationHistory.save([historyRecord])

        XCTAssertEqual(try coreDataStore.loadActiveItems(), [memoryItem])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [historyRecord])
    }
}
