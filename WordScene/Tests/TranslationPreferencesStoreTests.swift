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

    func testShareTranslationDefaultsToManualTranslateWithAutoSourceAndDefaultTarget() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        XCTAssertFalse(store.isShareAutoTranslateEnabled)
        XCTAssertEqual(store.shareSourceLanguage, .auto)
        XCTAssertEqual(store.shareTargetLanguage, .zh)
    }

    func testPersistsShareTranslationLanguageDirection() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        store.shareSourceLanguage = .es
        store.shareTargetLanguage = .en

        let reloadedStore = TranslationPreferencesStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.shareSourceLanguage, .es)
        XCTAssertEqual(reloadedStore.shareTargetLanguage, .en)
    }

    func testShareTargetFallsBackWhenItMatchesNonAutoSource() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        store.shareSourceLanguage = .en
        store.shareTargetLanguage = .en

        XCTAssertEqual(store.shareSourceLanguage, .en)
        XCTAssertEqual(store.shareTargetLanguage, .zh)
    }

    func testPersistsShareAutoTranslatePreference() {
        let defaults = makeDefaults()
        let store = TranslationPreferencesStore(defaults: defaults)

        store.isShareAutoTranslateEnabled = true

        XCTAssertTrue(TranslationPreferencesStore(defaults: defaults).isShareAutoTranslateEnabled)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranslationPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
