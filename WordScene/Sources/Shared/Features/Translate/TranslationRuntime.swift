import SwiftUI

struct TranslationRuntime: Sendable {
    let credentialStore: any CredentialStoring
    let translationClient: any TranslationClienting

    static func liveForProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TranslationRuntime {
        guard arguments.contains("-WordSceneUITest"),
              let mode = environment["WORDSCENE_UI_TEST_TRANSLATION_MODE"] else {
            return TranslationRuntime(
                credentialStore: KeychainCredentialStore(),
                translationClient: DeepSeekTranslationClient()
            )
        }

        return TranslationRuntime(
            credentialStore: UITestCredentialStore(token: "ui-test-token"),
            translationClient: UITestTranslationClient(mode: mode)
        )
    }
}

private struct TranslationRuntimeKey: EnvironmentKey {
    static let defaultValue = TranslationRuntime.liveForProcess()
}

extension EnvironmentValues {
    var translationRuntime: TranslationRuntime {
        get { self[TranslationRuntimeKey.self] }
        set { self[TranslationRuntimeKey.self] = newValue }
    }
}

private struct UITestCredentialStore: CredentialStoring {
    let token: String

    func save(_ value: String, account: String) throws {}

    func read(account: String) throws -> String? {
        token
    }

    func delete(account: String) throws {}
}

private struct UITestTranslationClient: TranslationClienting {
    let mode: String

    func translate(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) async throws -> String {
        switch mode {
        case "timeout":
            throw DeepSeekTranslationError.timedOut
        case "slow-success":
            try await Task.sleep(nanoseconds: 700_000_000)
            return "流式完成译文"
        default:
            return "你好，世界。"
        }
    }

    func streamTranslation(
        text: String,
        source: LanguageSelection,
        target: LanguageSelection,
        apiToken: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let mode = mode
            Task {
                switch mode {
                case "timeout":
                    continuation.finish(throwing: DeepSeekTranslationError.timedOut)

                case "slow-success":
                    continuation.yield("流式中间译文")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continuation.yield("流式完成译文")
                    continuation.finish()

                default:
                    continuation.yield("你好")
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    continuation.yield("你好，世界。")
                    continuation.finish()
                }
            }
        }
    }
}
