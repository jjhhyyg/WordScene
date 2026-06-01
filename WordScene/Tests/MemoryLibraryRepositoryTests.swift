import XCTest
@testable import WordScene

final class MemoryLibraryRepositoryTests: XCTestCase {
    private enum RepositoryTestError: Error, Equatable {
        case loadFailed
        case writeFailed
    }

    private struct FailingCoreDataStore: CoreDataMemoryDataStore {
        var activeItems: [MemoryItem] = []
        var loadError: Error?
        var writeError: Error?

        func upsert(_ item: MemoryItem) throws {
            if let writeError {
                throw writeError
            }
        }

        func loadActiveItems() throws -> [MemoryItem] {
            if let loadError {
                throw loadError
            }
            return activeItems
        }

        func softDelete(id: UUID, deletedAt: Date) throws {
            if let writeError {
                throw writeError
            }
        }

        func loadDeletionTombstones() throws -> [CoreDataDeletionTombstone] {
            []
        }

        func purgeDeletedItemsAndTombstones(olderThan cutoff: Date) throws -> Int {
            if let writeError {
                throw writeError
            }
            return 0
        }
    }

    func testSavesAndLoadsItemsFromCoreData() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let item = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        repository.save([item])

        XCTAssertEqual(repository.load(), [item])
    }

    func testSaveSoftDeletesItemsMissingFromReplacementSnapshot() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        repository.save([item])
        repository.save([])

        XCTAssertTrue(repository.load().isEmpty)
        XCTAssertEqual(try coreDataStore.loadDeletionTombstones().map(\.itemID), [item.id])
    }

    func testDeleteOrThrowSoftDeletesItemFromCoreData() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "delete me",
            translatedText: "删除我",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        try repository.saveOrThrow([item])
        try repository.deleteOrThrow(id: item.id)

        XCTAssertTrue(try repository.loadOrThrow().isEmpty)
        XCTAssertEqual(try coreDataStore.loadDeletionTombstones().map(\.itemID), [item.id])
    }

    func testDeleteAllOrThrowSoftDeletesAllItemsFromCoreData() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let first = MemoryItem(sourceText: "one", translatedText: "一", sourceLanguage: .en, targetLanguage: .zh)
        let second = MemoryItem(sourceText: "two", translatedText: "二", sourceLanguage: .en, targetLanguage: .zh)

        try repository.saveOrThrow([first, second])
        try repository.deleteAllOrThrow()

        XCTAssertTrue(try repository.loadOrThrow().isEmpty)
        XCTAssertEqual(Set(try coreDataStore.loadDeletionTombstones().map(\.itemID)), Set([first.id, second.id]))
    }

    func testToggleStarPersistsStarredState() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let item = MemoryItem(sourceText: "star", translatedText: "星", sourceLanguage: .en, targetLanguage: .zh)

        try repository.saveOrThrow([item])
        let updatedItem = try XCTUnwrap(repository.toggleStarOrThrow(id: item.id))

        XCTAssertTrue(updatedItem.isStarred)
        XCTAssertEqual(try repository.loadOrThrow().first?.isStarred, true)
    }

    func testDeleteOrThrowRemovesItemFromLegacyFallbackStore() throws {
        let suiteName = "MemoryLibraryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let item = MemoryItem(
            id: UUID(),
            sourceText: "legacy delete",
            translatedText: "旧删除",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let legacyStore = MemoryLibraryStore(defaults: defaults)
        legacyStore.save([item])
        let repository = MemoryLibraryRepository(
            coreDataStore: nil,
            legacyStore: legacyStore
        )

        try repository.deleteOrThrow(id: item.id)

        XCTAssertTrue(try repository.loadOrThrow().isEmpty)
    }

    func testSaveOrThrowDoesNotRecordChangeForIdenticalSnapshot() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        var changeCount = 0
        let repository = MemoryLibraryRepository(
            coreDataStore: coreDataStore,
            changeRecorder: {
                changeCount += 1
            }
        )
        let item = MemoryItem(
            id: UUID(),
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        try repository.saveOrThrow([item])
        try repository.saveOrThrow([item])

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(try coreDataStore.loadActiveItems(), [item])
    }

    func testMigratesLegacyDefaultsIntoCoreDataAndClearsLegacySource() throws {
        let suiteName = "MemoryLibraryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyStore = MemoryLibraryStore(defaults: defaults)
        let legacyItem = MemoryItem(
            sourceText: "legacy",
            translatedText: "旧",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        legacyStore.save([legacyItem])

        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyStore
        )

        XCTAssertEqual(repository.load(), [legacyItem])
        XCTAssertEqual(try coreDataStore.loadActiveItems(), [legacyItem])
        XCTAssertNil(defaults.data(forKey: "memoryLibrary"))
    }

    func testLoadOrThrowPropagatesCoreDataReadFailureInsteadOfFallingBackToLegacy() throws {
        let suiteName = "MemoryLibraryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyStore = MemoryLibraryStore(defaults: defaults)
        legacyStore.save([
            MemoryItem(sourceText: "legacy", translatedText: "旧", sourceLanguage: .en, targetLanguage: .zh)
        ])
        let repository = MemoryLibraryRepository(
            coreDataStore: FailingCoreDataStore(loadError: RepositoryTestError.loadFailed),
            legacyStore: legacyStore
        )

        XCTAssertThrowsError(try repository.loadOrThrow()) { error in
            XCTAssertEqual(error as? RepositoryTestError, .loadFailed)
        }
    }

    func testSaveOrThrowPropagatesCoreDataWriteFailure() {
        let repository = MemoryLibraryRepository(
            coreDataStore: FailingCoreDataStore(writeError: RepositoryTestError.writeFailed)
        )

        XCTAssertThrowsError(try repository.saveOrThrow([
            MemoryItem(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)
        ])) { error in
            XCTAssertEqual(error as? RepositoryTestError, .writeFailed)
        }
    }

    func testPurgeExpiredDeletionTombstonesUsesLocalRetentionCutoff() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let now = Date(timeIntervalSince1970: 10_000_000)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "old delete",
            translatedText: "旧删除",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: now.addingTimeInterval(-40 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-40 * 24 * 60 * 60)
        )

        try repository.saveOrThrow([item])
        try coreDataStore.softDelete(id: item.id, deletedAt: now.addingTimeInterval(-31 * 24 * 60 * 60))
        let purgedCount = try repository.purgeExpiredDeletionTombstones(
            policy: .localOnly(days: 30),
            now: now
        )

        XCTAssertEqual(purgedCount, 1)
        XCTAssertTrue(try repository.loadDeletionTombstones().isEmpty)
    }

    func testPurgeExpiredDeletionTombstonesKeepsUnexpiredCloudKitTombstones() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = MemoryLibraryRepository(coreDataStore: coreDataStore)
        let now = Date(timeIntervalSince1970: 10_000_000)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "recent delete",
            translatedText: "近期删除",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: now.addingTimeInterval(-20 * 24 * 60 * 60),
            updatedAt: now.addingTimeInterval(-20 * 24 * 60 * 60)
        )

        try repository.saveOrThrow([item])
        try coreDataStore.softDelete(id: item.id, deletedAt: now.addingTimeInterval(-89 * 24 * 60 * 60))
        let purgedCount = try repository.purgeExpiredDeletionTombstones(
            policy: .cloudKit(days: 90, requiresSuccessfulExport: true),
            now: now
        )

        XCTAssertEqual(purgedCount, 0)
        XCTAssertEqual(try repository.loadDeletionTombstones().map(\.itemID), [item.id])
    }
}
