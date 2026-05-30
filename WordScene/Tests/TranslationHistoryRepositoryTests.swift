import XCTest
@testable import WordScene

final class TranslationHistoryRepositoryTests: XCTestCase {
    private enum RepositoryTestError: Error, Equatable {
        case loadFailed
        case writeFailed
    }

    private struct FailingHistoryCoreDataStore: CoreDataTranslationHistoryDataStore {
        var historyRecords: [TranslationRecord] = []
        var loadError: Error?
        var writeError: Error?

        func loadHistoryRecords() throws -> [TranslationRecord] {
            if let loadError {
                throw loadError
            }
            return historyRecords
        }

        func replaceHistoryRecords(_ records: [TranslationRecord]) throws {
            if let writeError {
                throw writeError
            }
        }
    }

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

    func testDefaultMaximumCountKeepsRecentOneHundredRecords() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(coreDataStore: coreDataStore)
        let records = (0..<101).map { index in
            TranslationRecord(
                sourceText: "source \(index)",
                translatedText: "译文 \(index)",
                sourceLanguage: .en,
                targetLanguage: .zh,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        try repository.saveOrThrow(Array(records.reversed()))

        XCTAssertEqual(try repository.loadOrThrow().count, 100)
        XCTAssertEqual(try repository.loadOrThrow().first?.sourceText, "source 100")
        XCTAssertEqual(try repository.loadOrThrow().last?.sourceText, "source 1")
    }

    func testDeleteAllOrThrowClearsHistoryAndRecordsChange() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        var changeCount = 0
        let repository = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            changeRecorder: {
                changeCount += 1
            }
        )
        let record = TranslationRecord(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)

        try repository.saveOrThrow([record])
        try repository.deleteAllOrThrow()

        XCTAssertEqual(try repository.loadOrThrow(), [])
        XCTAssertEqual(changeCount, 2)
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

    func testAddingDuplicateTranslationMovesLatestRecordToTopWithoutDuplicate() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(coreDataStore: coreDataStore, maximumCount: 3)
        let oldRecord = TranslationRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let otherRecord = TranslationRecord(
            sourceText: "world",
            translatedText: "世界",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let latestDuplicate = TranslationRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sourceText: " hello ",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 30)
        )

        let records = repository.adding(latestDuplicate, to: [otherRecord, oldRecord])

        XCTAssertEqual(records.map(\.id), [latestDuplicate.id, otherRecord.id])
    }

    func testRemovingRecordByIDPreservesOtherHistoryRecords() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        let repository = TranslationHistoryRepository(coreDataStore: coreDataStore, maximumCount: 3)
        let removedRecord = TranslationRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let keptRecord = TranslationRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            sourceText: "world",
            translatedText: "世界",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 20)
        )

        let records = repository.removing(id: removedRecord.id, from: [keptRecord, removedRecord])

        XCTAssertEqual(records, [keptRecord])
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

    func testLoadOrThrowPropagatesCoreDataReadFailureInsteadOfFallingBackToLegacy() throws {
        let suiteName = "TranslationHistoryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacyStore = TranslationHistoryStore(defaults: defaults)
        legacyStore.save([
            TranslationRecord(sourceText: "legacy", translatedText: "旧", sourceLanguage: .en, targetLanguage: .zh)
        ])
        let repository = TranslationHistoryRepository(
            coreDataStore: FailingHistoryCoreDataStore(loadError: RepositoryTestError.loadFailed),
            legacyStore: legacyStore
        )

        XCTAssertThrowsError(try repository.loadOrThrow()) { error in
            XCTAssertEqual(error as? RepositoryTestError, .loadFailed)
        }
    }

    func testSaveOrThrowPropagatesCoreDataWriteFailure() {
        let repository = TranslationHistoryRepository(
            coreDataStore: FailingHistoryCoreDataStore(writeError: RepositoryTestError.writeFailed)
        )

        XCTAssertThrowsError(try repository.saveOrThrow([
            TranslationRecord(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)
        ])) { error in
            XCTAssertEqual(error as? RepositoryTestError, .writeFailed)
        }
    }

    func testSaveOrThrowDoesNotRecordChangeForIdenticalSnapshot() throws {
        let coreDataStore = try CoreDataMemoryStore(inMemory: true)
        var changeCount = 0
        let repository = TranslationHistoryRepository(
            coreDataStore: coreDataStore,
            changeRecorder: {
                changeCount += 1
            }
        )
        let record = TranslationRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )

        try repository.saveOrThrow([record])
        try repository.saveOrThrow([record])

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(try coreDataStore.loadHistoryRecords(), [record])
    }

    func testSaveOrThrowDoesNotRecordChangeForIdenticalLegacySnapshot() throws {
        let suiteName = "TranslationHistoryRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var changeCount = 0
        let legacyStore = TranslationHistoryStore(defaults: defaults)
        let repository = TranslationHistoryRepository(
            coreDataStore: nil,
            legacyStore: legacyStore,
            changeRecorder: {
                changeCount += 1
            }
        )
        let record = TranslationRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            createdAt: Date(timeIntervalSince1970: 10)
        )

        try repository.saveOrThrow([record])
        try repository.saveOrThrow([record])

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(try legacyStore.loadOrThrow(), [record])
    }
}
