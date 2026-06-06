import Foundation
import XCTest
@testable import WordScene

@MainActor
final class ShareTranslationViewModelTests: XCTestCase {
    func testLoadWaitsForManualTranslateWhenAutoTranslateIsDisabled() async throws {
        let defaults = makeDefaults()
        let preferencesStore = TranslationPreferencesStore(defaults: defaults)
        preferencesStore.isShareAutoTranslateEnabled = false
        preferencesStore.shareSourceLanguage = .es
        preferencesStore.shareTargetLanguage = .en
        let translationClient = StubShareTranslationClient(translatedText: "hello")
        let viewModel = makeViewModel(preferencesStore: preferencesStore, translationClient: translationClient)

        viewModel.load(providers: [NSItemProvider(object: "hola" as NSString)])
        try await waitUntil {
            if case .ready = viewModel.state {
                return true
            }
            return false
        }

        XCTAssertEqual(viewModel.sourceLanguage, .es)
        XCTAssertEqual(viewModel.targetLanguage, .en)
        XCTAssertEqual(translationClient.requests, [])
    }

    func testManualTranslateUsesShareLanguagePreferenceAndPersistsDirection() async throws {
        let defaults = makeDefaults()
        let preferencesStore = TranslationPreferencesStore(defaults: defaults)
        preferencesStore.isShareAutoTranslateEnabled = false
        preferencesStore.shareSourceLanguage = .es
        preferencesStore.shareTargetLanguage = .en
        let translationClient = StubShareTranslationClient(translatedText: "hello")
        let viewModel = makeViewModel(preferencesStore: preferencesStore, translationClient: translationClient)

        viewModel.load(providers: [NSItemProvider(object: "hola" as NSString)])
        try await waitUntil {
            if case .ready = viewModel.state {
                return true
            }
            return false
        }
        await viewModel.translateCurrentText()

        XCTAssertEqual(translationClient.requests, [
            TranslationProviderRequest(text: "hola", source: .es, target: .en)
        ])
        XCTAssertEqual(preferencesStore.shareSourceLanguage, .es)
        XCTAssertEqual(preferencesStore.shareTargetLanguage, .en)
    }

    func testManualTranslateRecordsProviderDetectedSourceLanguage() async throws {
        let defaults = makeDefaults()
        let preferencesStore = TranslationPreferencesStore(defaults: defaults)
        preferencesStore.isShareAutoTranslateEnabled = false
        preferencesStore.shareSourceLanguage = .auto
        preferencesStore.shareTargetLanguage = .en
        let translationClient = StubShareTranslationClient(translatedText: "But why?", detectedSourceLanguage: .zh)
        let viewModel = makeViewModel(preferencesStore: preferencesStore, translationClient: translationClient)

        viewModel.load(providers: [NSItemProvider(object: "不过为啥" as NSString)])
        try await waitUntil {
            if case .ready = viewModel.state {
                return true
            }
            return false
        }
        await viewModel.translateCurrentText()

        guard case .translated(let record) = viewModel.state else {
            return XCTFail("Expected translated share state.")
        }
        XCTAssertEqual(record.sourceLanguage, .zh)
        XCTAssertEqual(record.targetLanguage, .en)
    }

    func testLoadAutoTranslatesWithShareLanguagePreference() async throws {
        let defaults = makeDefaults()
        let preferencesStore = TranslationPreferencesStore(defaults: defaults)
        preferencesStore.isShareAutoTranslateEnabled = true
        preferencesStore.shareSourceLanguage = .es
        preferencesStore.shareTargetLanguage = .en
        let translationClient = StubShareTranslationClient(translatedText: "hello")
        let viewModel = makeViewModel(preferencesStore: preferencesStore, translationClient: translationClient)

        viewModel.load(providers: [NSItemProvider(object: "hola" as NSString)])
        try await waitUntil {
            if case .translated = viewModel.state {
                return true
            }
            return false
        }

        XCTAssertEqual(translationClient.requests, [
            TranslationProviderRequest(text: "hola", source: .es, target: .en)
        ])
    }

    func testChangingLanguageAfterTranslationRetranslatesAndPersistsDirection() async throws {
        let defaults = makeDefaults()
        let preferencesStore = TranslationPreferencesStore(defaults: defaults)
        preferencesStore.isShareAutoTranslateEnabled = true
        preferencesStore.shareSourceLanguage = .es
        preferencesStore.shareTargetLanguage = .en
        let translationClient = StubShareTranslationClient(translatedText: "hello")
        let viewModel = makeViewModel(preferencesStore: preferencesStore, translationClient: translationClient)

        viewModel.load(providers: [NSItemProvider(object: "hola" as NSString)])
        try await waitUntil {
            if case .translated = viewModel.state {
                return true
            }
            return false
        }
        viewModel.updateTargetLanguage(.zh)
        try await waitUntil {
            translationClient.requests.count == 2
        }

        XCTAssertEqual(translationClient.requests, [
            TranslationProviderRequest(text: "hola", source: .es, target: .en),
            TranslationProviderRequest(text: "hola", source: .es, target: .zh)
        ])
        XCTAssertEqual(preferencesStore.shareSourceLanguage, .es)
        XCTAssertEqual(preferencesStore.shareTargetLanguage, .zh)
    }

    private func makeViewModel(
        preferencesStore: TranslationPreferencesStore,
        translationClient: StubShareTranslationClient
    ) -> ShareTranslationViewModel {
        ShareTranslationViewModel(
            credentialStore: StubShareCredentialStore(token: "test-token"),
            translationClient: translationClient,
            handoffStore: nil,
            preferencesStore: preferencesStore
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ShareTranslationViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct StubShareCredentialStore: CredentialStoring {
    let token: String?

    func save(_ value: String, account: String) throws {}

    func read(account: String) throws -> String? {
        token
    }

    func delete(account: String) throws {}
}

private final class StubShareTranslationClient: TranslationClienting, @unchecked Sendable {
    let translatedText: String
    let detectedSourceLanguage: LanguageSelection
    private(set) var requests: [TranslationProviderRequest] = []

    init(translatedText: String, detectedSourceLanguage: LanguageSelection = .es) {
        self.translatedText = translatedText
        self.detectedSourceLanguage = detectedSourceLanguage
    }

    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> TranslationLLMResult {
        XCTAssertEqual(apiToken, "test-token")
        requests.append(TranslationProviderRequest(text: text, source: source, target: target))
        return TranslationLLMResult(
            translatedText: translatedText,
            detectedSourceLanguage: detectedSourceLanguage
        )
    }
}
