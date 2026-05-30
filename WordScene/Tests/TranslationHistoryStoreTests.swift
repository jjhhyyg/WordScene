import XCTest
@testable import WordScene

final class TranslationHistoryStoreTests: XCTestCase {
    func testPersistsRecentRecords() {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = TranslationHistoryStore(defaults: defaults, maximumCount: 2)
        let first = TranslationRecord(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)
        let second = TranslationRecord(sourceText: "world", translatedText: "世界", sourceLanguage: .en, targetLanguage: .zh)
        let third = TranslationRecord(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)

        let records = store.adding(third, to: store.adding(second, to: store.adding(first, to: [])))
        store.save(records)

        let loaded = store.load()
        XCTAssertEqual(loaded.map(\.sourceText), ["cat", "world"])
    }

    func testAddingDuplicateTranslationMovesLatestRecordToTopWithoutDuplicate() {
        let store = TranslationHistoryStore(defaults: UserDefaults.standard, maximumCount: 3)
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

        let records = store.adding(latestDuplicate, to: [otherRecord, oldRecord])

        XCTAssertEqual(records.map(\.id), [latestDuplicate.id, otherRecord.id])
        XCTAssertEqual(records.first?.sourceText, " hello ")
    }

    func testSavesVersionedDocumentForFutureMigrations() throws {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = TranslationHistoryStore(defaults: defaults)
        let record = TranslationRecord(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)

        store.save([record])

        let data = try XCTUnwrap(defaults.data(forKey: "translationHistory"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual((object["records"] as? [[String: Any]])?.count, 1)
    }

    func testLoadsLegacyArrayAndMigratesToVersionedDocument() throws {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = TranslationHistoryStore(defaults: defaults)
        let record = TranslationRecord(sourceText: "legacy", translatedText: "旧", sourceLanguage: .en, targetLanguage: .zh)
        defaults.set(try JSONEncoder().encode([record]), forKey: "translationHistory")

        XCTAssertEqual(store.load(), [record])

        let migratedData = try XCTUnwrap(defaults.data(forKey: "translationHistory"))
        let migratedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(migratedObject["schema_version"] as? Int, 1)
        XCTAssertEqual((migratedObject["records"] as? [[String: Any]])?.first?["sourceText"] as? String, "legacy")
    }

    func testLoadOrThrowRejectsUnreadableDocumentWithoutClearingData() throws {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = TranslationHistoryStore(defaults: defaults)
        let corruptData = Data("{not json".utf8)
        defaults.set(corruptData, forKey: "translationHistory")

        XCTAssertThrowsError(try store.loadOrThrow()) { error in
            XCTAssertEqual(error as? LocalPersistenceStoreError, .unreadableDocument(key: "translationHistory"))
        }
        XCTAssertEqual(defaults.data(forKey: "translationHistory"), corruptData)
    }

    func testLoadOrThrowRejectsUnsupportedSchemaVersionWithoutClearingData() throws {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = TranslationHistoryStore(defaults: defaults)
        let futureDocument = Data(#"{"schema_version":99,"records":[]}"#.utf8)
        defaults.set(futureDocument, forKey: "translationHistory")

        XCTAssertThrowsError(try store.loadOrThrow()) { error in
            XCTAssertEqual(
                error as? LocalPersistenceStoreError,
                .unsupportedSchemaVersion(key: "translationHistory", version: 99)
            )
        }
        XCTAssertEqual(defaults.data(forKey: "translationHistory"), futureDocument)
    }
}
