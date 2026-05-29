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
}
