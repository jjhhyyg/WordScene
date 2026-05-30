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
}
