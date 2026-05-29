import XCTest
@testable import WordScene

final class MemoryLibraryRepositoryTests: XCTestCase {
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
}
