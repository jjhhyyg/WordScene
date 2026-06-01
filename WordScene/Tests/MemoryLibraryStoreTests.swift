import XCTest
@testable import WordScene

final class MemoryLibraryStoreTests: XCTestCase {
    func testPersistsSavedItemsWithNotes() {
        let suiteName = "MemoryLibraryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MemoryLibraryStore(defaults: defaults)
        let item = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting"
        )

        store.save([item])

        XCTAssertEqual(store.load(), [item])
    }

    func testSavesVersionedDocumentForFutureMigrations() throws {
        let suiteName = "MemoryLibraryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MemoryLibraryStore(defaults: defaults)
        let item = MemoryItem(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)

        store.save([item])

        let data = try XCTUnwrap(defaults.data(forKey: "memoryLibrary"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual((object["items"] as? [[String: Any]])?.count, 1)
    }

    func testLoadsLegacyArrayAndMigratesToVersionedDocument() throws {
        let suiteName = "MemoryLibraryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MemoryLibraryStore(defaults: defaults)
        let item = MemoryItem(sourceText: "legacy", translatedText: "旧", sourceLanguage: .en, targetLanguage: .zh)
        defaults.set(try JSONEncoder().encode([item]), forKey: "memoryLibrary")

        XCTAssertEqual(store.load(), [item])

        let migratedData = try XCTUnwrap(defaults.data(forKey: "memoryLibrary"))
        let migratedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: migratedData) as? [String: Any])
        XCTAssertEqual(migratedObject["schema_version"] as? Int, 1)
        XCTAssertEqual((migratedObject["items"] as? [[String: Any]])?.first?["sourceText"] as? String, "legacy")
    }

    func testLoadOrThrowRejectsUnreadableDocumentWithoutClearingData() throws {
        let suiteName = "MemoryLibraryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MemoryLibraryStore(defaults: defaults)
        let corruptData = Data("{not json".utf8)
        defaults.set(corruptData, forKey: "memoryLibrary")

        XCTAssertThrowsError(try store.loadOrThrow()) { error in
            XCTAssertEqual(error as? LocalPersistenceStoreError, .unreadableDocument(key: "memoryLibrary"))
        }
        XCTAssertEqual(defaults.data(forKey: "memoryLibrary"), corruptData)
    }

    func testLoadOrThrowRejectsUnsupportedSchemaVersionWithoutClearingData() throws {
        let suiteName = "MemoryLibraryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = MemoryLibraryStore(defaults: defaults)
        let futureDocument = Data(#"{"schema_version":99,"items":[]}"#.utf8)
        defaults.set(futureDocument, forKey: "memoryLibrary")

        XCTAssertThrowsError(try store.loadOrThrow()) { error in
            XCTAssertEqual(
                error as? LocalPersistenceStoreError,
                .unsupportedSchemaVersion(key: "memoryLibrary", version: 99)
            )
        }
        XCTAssertEqual(defaults.data(forKey: "memoryLibrary"), futureDocument)
    }

    func testAddingSameTranslationDoesNotCreateDuplicate() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let record = TranslationRecord(
            sourceText: " hello ",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        let first = store.adding(record, to: [])
        let second = store.adding(record, to: first)

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.sourceText, "hello")
    }

    func testAddingDetectedRecordReplacesLegacyAutoDuplicate() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let legacyItem = MemoryItem(
            sourceText: "Hola",
            translatedText: "你好",
            sourceLanguage: .auto,
            targetLanguage: .zh,
            note: "old"
        )
        let detectedRecord = TranslationRecord(
            sourceText: "Hola",
            translatedText: "你好",
            sourceLanguage: .es,
            targetLanguage: .zh
        )

        let items = store.adding(detectedRecord, to: [legacyItem])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceLanguage, .es)
        XCTAssertEqual(items.first?.note, "")
    }

    func testAddingManualItemTrimsAndDeduplicatesSavedMemory() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let manualItem = MemoryItem(
            sourceText: " HELLO ",
            translatedText: " 你好 ",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: " greeting "
        )
        let existingItem = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old"
        )

        let items = store.adding(manualItem, to: [existingItem])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceText, "HELLO")
        XCTAssertEqual(items.first?.translatedText, "你好")
        XCTAssertEqual(items.first?.note, "greeting")
    }

    func testAddingManualItemDeduplicatesCaseInsensitiveText() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let existingItem = MemoryItem(
            sourceText: "Hello",
            translatedText: "Cat",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old"
        )
        let incomingItem = MemoryItem(
            sourceText: " hello ",
            translatedText: " cat ",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "new"
        )

        let items = store.adding(incomingItem, to: [existingItem])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceText, "hello")
        XCTAssertEqual(items.first?.translatedText, "cat")
        XCTAssertEqual(items.first?.note, "new")
    }

    func testAddingManualItemRejectsBlankSourceOrTranslation() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let existingItem = MemoryItem(sourceText: "cat", translatedText: "猫", sourceLanguage: .en, targetLanguage: .zh)

        let withoutSource = store.adding(
            MemoryItem(sourceText: " ", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh),
            to: [existingItem]
        )
        let withoutTranslation = store.adding(
            MemoryItem(sourceText: "hello", translatedText: "\n", sourceLanguage: .en, targetLanguage: .zh),
            to: [existingItem]
        )

        XCTAssertEqual(withoutSource, [existingItem])
        XCTAssertEqual(withoutTranslation, [existingItem])
    }

    func testRemovesMatchingTranslation() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let record = TranslationRecord(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let items = store.adding(record, to: [])

        XCTAssertTrue(store.removing(record, from: items).isEmpty)
    }

    func testUpdatesNoteForSavedItem() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let updatedItems = store.updatingNote(for: item.id, note: "常用问候", in: [item])

        XCTAssertEqual(updatedItems.first?.note, "常用问候")
        XCTAssertGreaterThan(updatedItems.first?.updatedAt ?? item.updatedAt, item.updatedAt)
    }

    func testUpdatingNoteWithSameTrimmedValueDoesNotTouchTimestamp() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let item = MemoryItem(
            id: UUID(),
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "常用问候",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let updatedItems = store.updatingNote(for: item.id, note: "  常用问候\n", in: [item])

        XCTAssertEqual(updatedItems, [item])
    }

    func testUpdatingItemTrimsFieldsPreservesCreatedAtAndTouchesUpdatedAt() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let id = UUID()
        let original = MemoryItem(
            id: id,
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "old",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let replacement = MemoryItem(
            id: id,
            sourceText: "  good morning ",
            translatedText: "  早上好\n",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: " updated ",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let updatedItems = store.updatingItem(replacement, in: [original])

        XCTAssertEqual(updatedItems.first?.id, id)
        XCTAssertEqual(updatedItems.first?.sourceText, "good morning")
        XCTAssertEqual(updatedItems.first?.translatedText, "早上好")
        XCTAssertEqual(updatedItems.first?.note, "updated")
        XCTAssertEqual(updatedItems.first?.createdAt, original.createdAt)
        XCTAssertGreaterThan(updatedItems.first?.updatedAt ?? original.updatedAt, original.updatedAt)
    }

    func testUpdatingItemRejectsBlankSourceOrTranslation() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let original = MemoryItem(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)

        let blankSource = MemoryItem(
            id: original.id,
            sourceText: " ",
            translatedText: "updated",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let blankTranslation = MemoryItem(
            id: original.id,
            sourceText: "updated",
            translatedText: "\n",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        XCTAssertEqual(store.updatingItem(blankSource, in: [original]), [original])
        XCTAssertEqual(store.updatingItem(blankTranslation, in: [original]), [original])
    }

    func testUpdatingItemLeavesUnchangedSnapshotUntouched() {
        let store = MemoryLibraryStore(defaults: UserDefaults.standard)
        let original = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let replacement = MemoryItem(
            id: original.id,
            sourceText: "  hello\n",
            translatedText: "  你好 ",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: " greeting ",
            createdAt: Date(timeIntervalSince1970: 30),
            updatedAt: Date(timeIntervalSince1970: 40)
        )

        XCTAssertEqual(store.updatingItem(replacement, in: [original]), [original])
    }
}
