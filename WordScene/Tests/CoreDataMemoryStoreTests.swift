import XCTest
@testable import WordScene

final class CoreDataMemoryStoreTests: XCTestCase {
    func testPersistentStoreDescriptionConfiguresCloudKitSyncOptions() {
        let storeURL = URL(fileURLWithPath: "/tmp/WordScene.sqlite")

        let description = CoreDataMemoryStore.makeStoreDescription(
            inMemory: false,
            syncMode: .cloudKit(containerIdentifier: "iCloud.com.erikssonhou.leximemory"),
            storeURL: storeURL
        )

        XCTAssertEqual(description.url, storeURL)
        XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.com.erikssonhou.leximemory")
        XCTAssertEqual(description.options[NSPersistentHistoryTrackingKey] as? NSNumber, true)
        XCTAssertEqual(description.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber, true)
    }

    func testSavesAndLoadsActiveMemoryItems() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try store.upsert(item)

        XCTAssertEqual(try store.loadActiveItems(), [item])
    }

    func testSoftDeleteHidesItemAndWritesTombstone() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let id = UUID()
        let item = MemoryItem(
            id: id,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let deletedAt = Date(timeIntervalSince1970: 30)
        try store.upsert(item)

        try store.softDelete(id: id, deletedAt: deletedAt)

        XCTAssertTrue(try store.loadActiveItems().isEmpty)
        XCTAssertEqual(try store.loadDeletionTombstones(), [
            CoreDataDeletionTombstone(itemID: id, deletedAt: deletedAt)
        ])
    }
}
