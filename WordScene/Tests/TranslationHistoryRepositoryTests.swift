import XCTest
@testable import WordScene

final class TranslationHistoryRepositoryTests: XCTestCase {
    func testSavesAndLoadsRecentRecordsFromCoreData() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(coreDataStore: coreDataStore, maximumCount: 2)
        let first = TranslationRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let second = TranslationRecord(
            sourceText: "world",
            translatedText: "世界",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let third = TranslationRecord(
            sourceText: "cat",
            translatedText: "猫",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 30)
        )

        repository.save([third, second, first])

        XCTAssertEqual(repository.load(), [third, second])
    }

    func testAddingPrependsAndCapsRecentRecords() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(coreDataStore: coreDataStore, maximumCount: 2)
        let first = TranslationRecord(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)
        let second = TranslationRecord(sourceText: "world", translatedText: "世界", sourceLanguage: .en, targetLanguage: .zh)
        let third = TranslationRecord(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)

        let records: [TranslationRecord] = repository.adding(
            third,
            to: repository.adding(second, to: repository.adding(first, to: []))
        )

        XCTAssertEqual(records.map(\.sourceText), ["cat", "world"])
    }

    func testMigratesLegacyDefaultsIntoCoreDataAndClearsLegacySource() throws {
        let suiteName = "TranslationHistoryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyStore = TranslationHistoryStore(defaults: defaults)
        let legacyRecord = TranslationRecord(
            sourceText: "legacy",
            translatedText: "旧",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        legacyStore.save([legacyRecord])

        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            legacyStore: legacyStore
        )

        XCTAssertEqual(repository.load(), [legacyRecord])
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [legacyRecord])
        XCTAssertNil(defaults.data(forKey: "translationHistory"))
    }
}
