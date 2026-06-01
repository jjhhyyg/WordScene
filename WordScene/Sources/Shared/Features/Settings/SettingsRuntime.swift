import SwiftUI

protocol DeepSeekBalanceFetching: Sendable {
    func fetchBalance(apiToken: String) async throws -> DeepSeekBalanceResponse
}

struct SettingsRuntime: Sendable {
    let credentialStore: any CredentialStoring
    let balanceClient: any DeepSeekBalanceFetching
    let memoryExportURL: URL?
    let memoryImportURL: URL?

    static func liveForProcess(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SettingsRuntime {
        guard arguments.contains("-WordSceneUITest") else {
            return SettingsRuntime(
                credentialStore: KeychainCredentialStore(),
                balanceClient: DeepSeekBalanceClient(),
                memoryExportURL: nil,
                memoryImportURL: nil
            )
        }

        return SettingsRuntime(
            credentialStore: SettingsUITestCredentialStore(
                initialToken: environment["WORDSCENE_UI_TEST_DEEPSEEK_TOKEN"]
            ),
            balanceClient: SettingsUITestBalanceClient(
                mode: environment["WORDSCENE_UI_TEST_DEEPSEEK_TOKEN_MODE"] ?? "success"
            ),
            memoryExportURL: environment["WORDSCENE_UI_TEST_MEMORY_EXPORT_URL"].map(URL.init(fileURLWithPath:)),
            memoryImportURL: environment["WORDSCENE_UI_TEST_MEMORY_IMPORT_URL"].map(URL.init(fileURLWithPath:))
        )
    }
}

private struct SettingsRuntimeKey: EnvironmentKey {
    static let defaultValue = SettingsRuntime.liveForProcess()
}

extension EnvironmentValues {
    var settingsRuntime: SettingsRuntime {
        get { self[SettingsRuntimeKey.self] }
        set { self[SettingsRuntimeKey.self] = newValue }
    }
}

private final class SettingsUITestCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: String]

    init(initialToken: String?) {
        if let initialToken {
            storedValues = [DeepSeekCredential.tokenAccount: initialToken]
        } else {
            storedValues = [:]
        }
    }

    func save(_ value: String, account: String) throws {
        lock.withLock {
            storedValues[account] = value
        }
    }

    func read(account: String) throws -> String? {
        lock.withLock {
            storedValues[account]
        }
    }

    func delete(account: String) throws {
        lock.withLock {
            _ = storedValues.removeValue(forKey: account)
        }
    }
}

private struct SettingsUITestBalanceClient: DeepSeekBalanceFetching {
    let mode: String

    func fetchBalance(apiToken: String) async throws -> DeepSeekBalanceResponse {
        switch mode {
        case "unauthorized":
            throw DeepSeekBalanceError.unauthorized
        case "unavailable-balance":
            throw DeepSeekBalanceError.unavailableBalance
        default:
            return DeepSeekBalanceResponse(
                isAvailable: true,
                balanceInfos: [
                    DeepSeekBalanceResponse.BalanceInfo(
                        currency: "CNY",
                        totalBalance: "1.00",
                        grantedBalance: "1.00",
                        toppedUpBalance: "0.00"
                    )
                ]
            )
        }
    }
}
