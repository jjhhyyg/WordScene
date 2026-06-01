import CoreData
import XCTest
@testable import WordScene

final class CoreDataMemoryStoreTests: XCTestCase {
    func testDefaultSyncModeFallsBackToLocalOnlyWithoutCloudKitEntitlements() {
        let syncMode = CoreDataSyncMode.defaultForCurrentProcess(
            isCloudSyncEnabled: { true },
            entitlementValue: { _ in nil }
        )

        XCTAssertEqual(syncMode, .localOnly)
    }

    #if targetEnvironment(simulator)
    func testDefaultSyncModeUsesLocalOnlyForSimulatorTestHosts() {
        XCTAssertEqual(CoreDataSyncMode.defaultForCurrentProcess(), .localOnly)
    }
    #endif

    func testDefaultSyncModeStaysLocalWhenCloudKitIsNotRequested() {
        let syncMode = CoreDataSyncMode.defaultForCurrentProcess(
            isCloudSyncEnabled: { false },
            entitlementValue: { entitlement in
                switch entitlement {
                case "com.apple.developer.icloud-services":
                    return ["CloudKit"]
                case "com.apple.developer.icloud-container-identifiers":
                    return [CoreDataMemoryStore.productionCloudKitContainerIdentifier]
                default:
                    return nil
                }
            }
        )

        XCTAssertEqual(syncMode, .localOnly)
    }

    func testDefaultSyncModeUsesCloudKitWhenRequestedAndEntitlementsMatchContainer() {
        let syncMode = CoreDataSyncMode.defaultForCurrentProcess(
            isCloudSyncEnabled: { true },
            entitlementValue: { entitlement in
                switch entitlement {
                case "com.apple.developer.icloud-services":
                    return ["CloudKit"]
                case "com.apple.developer.icloud-container-identifiers":
                    return [CoreDataMemoryStore.productionCloudKitContainerIdentifier]
                default:
                    return nil
                }
            }
        )

        XCTAssertEqual(
            syncMode,
            .cloudKit(containerIdentifier: CoreDataMemoryStore.productionCloudKitContainerIdentifier)
        )
    }

    func testCloudKitSyncedAttributesAreOptionalOrDefaulted() {
        let failures = CoreDataMemoryStore.cloudKitModelValidationFailures()

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: ", "))
    }

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

    func testPersistentLocalStoreDescriptionKeepsHistoryTrackingEnabled() {
        let storeURL = URL(fileURLWithPath: "/tmp/WordScene.sqlite")

        let description = CoreDataMemoryStore.makeStoreDescription(
            inMemory: false,
            syncMode: .localOnly,
            storeURL: storeURL
        )

        XCTAssertEqual(description.url, storeURL)
        XCTAssertNil(description.cloudKitContainerOptions)
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

    func testSavesAndLoadsStarredMemoryItems() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "starred",
            translatedText: "星标",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            isStarred: true
        )

        try store.upsert(item)

        XCTAssertEqual(try store.loadActiveItems().first?.isStarred, true)
    }

    func testDuplicateKeyNormalizesCaseInsensitiveText() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let first = MemoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceText: " Hello ",
            translatedText: " Cat ",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let duplicate = MemoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sourceText: "hello",
            translatedText: "cat",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 20),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try store.upsert(first)
        try store.upsert(duplicate)

        XCTAssertEqual(try store.loadActiveItems().count, 1)
        XCTAssertEqual(try store.loadActiveItems().first?.id, duplicate.id)
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

    func testUpsertDoesNotReviveItemWhenTombstoneIsNewerThanIncomingRecord() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let id = UUID()
        let item = MemoryItem(
            id: id,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try store.upsert(item)
        try store.softDelete(id: id, deletedAt: Date(timeIntervalSince1970: 30))

        try store.upsert(item)

        XCTAssertTrue(try store.loadActiveItems().isEmpty)
        XCTAssertEqual(try store.loadDeletionTombstones().map(\.itemID), [id])
    }

    func testUpsertAllowsRecordNewerThanTombstoneToBecomeActive() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let id = UUID()
        let original = MemoryItem(
            id: id,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let newer = MemoryItem(
            id: id,
            sourceText: "hello again",
            translatedText: "再次你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        try store.upsert(original)
        try store.softDelete(id: id, deletedAt: Date(timeIntervalSince1970: 30))

        try store.upsert(newer)

        XCTAssertEqual(try store.loadActiveItems(), [newer])
    }

    func testPurgeRemovesExpiredTombstoneAndSoftDeletedItem() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let id = UUID()
        let item = MemoryItem(
            id: id,
            sourceText: "old",
            translatedText: "旧",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try store.upsert(item)
        try store.softDelete(id: id, deletedAt: Date(timeIntervalSince1970: 30))

        let purgedCount = try store.purgeDeletedItemsAndTombstones(
            olderThan: Date(timeIntervalSince1970: 40)
        )
        try store.upsert(item)

        XCTAssertEqual(purgedCount, 1)
        XCTAssertTrue(try store.loadDeletionTombstones().isEmpty)
        XCTAssertEqual(try store.loadActiveItems(), [item])
    }

    func testPurgeKeepsUnexpiredTombstone() throws {
        let store = try CoreDataMemoryStore(inMemory: true)
        let id = UUID()
        let item = MemoryItem(
            id: id,
            sourceText: "recent",
            translatedText: "最近",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        try store.upsert(item)
        try store.softDelete(id: id, deletedAt: Date(timeIntervalSince1970: 30))

        let purgedCount = try store.purgeDeletedItemsAndTombstones(
            olderThan: Date(timeIntervalSince1970: 20)
        )
        try store.upsert(item)

        XCTAssertEqual(purgedCount, 0)
        XCTAssertEqual(try store.loadDeletionTombstones().map(\.itemID), [id])
        XCTAssertTrue(try store.loadActiveItems().isEmpty)
    }
}
