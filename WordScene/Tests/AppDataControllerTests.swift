import XCTest
@testable import WordScene

final class AppDataControllerTests: XCTestCase {
    private enum StoreBootstrapError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Core Data store unavailable"
        }
    }

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

    func testReportsPrimaryPersistenceWhenCoreDataLoads() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let controller = AppDataController(
            coreDataStoreFactory: { coreDataStore },
            syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier)
        )

        XCTAssertEqual(
            controller.persistenceStatus,
            .coreDataAvailable(syncMode: .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier))
        )
        XCTAssertEqual(controller.persistenceStatus.title, "Core Data + iCloud 已启用")
    }

    func testReportsFallbackPersistenceWhenCoreDataBootstrapFails() {
        let controller = AppDataController(coreDataStoreFactory: {
            throw StoreBootstrapError.unavailable
        })

        XCTAssertEqual(
            controller.persistenceStatus,
            .legacyFallback(reason: "Core Data store unavailable")
        )
    }
}
