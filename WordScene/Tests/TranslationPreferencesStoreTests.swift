import XCTest
@testable import WordScene

final class TranslationPreferencesStoreTests: XCTestCase {
    func testDefaultsToSimplifiedChineseTargetLanguage() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        XCTAssertEqual(store.defaultTargetLanguage, .zh)
    }

    func testPersistsDefaultTargetLanguage() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        store.defaultTargetLanguage = .en

        XCTAssertEqual(TranslationPreferencesStore(defaults: defaults).defaultTargetLanguage, .en)
    }

    func testRejectsAutoAsDefaultTargetLanguage() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        store.defaultTargetLanguage = .auto

        XCTAssertEqual(store.defaultTargetLanguage, .zh)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranslationPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
