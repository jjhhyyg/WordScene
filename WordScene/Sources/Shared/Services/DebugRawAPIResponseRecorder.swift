import Foundation

#if DEBUG
struct DebugRawAPIResponse: Codable, Equatable, Sendable {
    let provider: String
    let endpoint: String
    let statusCode: Int
    let body: String
    let capturedAt: Date
}

enum DebugRawAPIResponseSettings {
    static let isEnabledKey = "storesRawAPIResponses"
}

actor DebugRawAPIResponseUserDefaultsStore {
    private let userDefaults: UserDefaults
    private let key: String
    private let limit: Int

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "debugRawAPIResponses",
        limit: Int = 20
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.limit = limit
    }

    init(
        suiteName: String,
        key: String = "debugRawAPIResponses",
        limit: Int = 20
    ) {
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = key
        self.limit = limit
    }

    func save(_ response: DebugRawAPIResponse) {
        var responses = load()
        responses.insert(response, at: 0)
        responses = Array(responses.prefix(limit))

        guard let data = try? JSONEncoder().encode(responses) else {
            return
        }
        userDefaults.set(data, forKey: key)
    }

    func load() -> [DebugRawAPIResponse] {
        guard let data = userDefaults.data(forKey: key),
              let responses = try? JSONDecoder().decode([DebugRawAPIResponse].self, from: data) else {
            return []
        }
        return responses
    }
}

struct DebugRawAPIResponseRecorder: Sendable {
    private let isEnabledProvider: @Sendable () -> Bool
    private let recordHandler: @Sendable (DebugRawAPIResponse) async -> Void
    private let dateProvider: @Sendable () -> Date

    init(
        isEnabled: @escaping @Sendable () -> Bool,
        dateProvider: @escaping @Sendable () -> Date = Date.init,
        record: @escaping @Sendable (DebugRawAPIResponse) async -> Void
    ) {
        self.isEnabledProvider = isEnabled
        self.dateProvider = dateProvider
        self.recordHandler = record
    }

    func record(
        provider: String,
        endpoint: URL,
        statusCode: Int,
        bodyData: Data
    ) async {
        guard isEnabledProvider() else {
            return
        }

        await recordHandler(
            DebugRawAPIResponse(
                provider: provider,
                endpoint: endpoint.absoluteString,
                statusCode: statusCode,
                body: String(data: bodyData, encoding: .utf8) ?? "",
                capturedAt: dateProvider()
            )
        )
    }

    static func userDefaultsBacked() -> DebugRawAPIResponseRecorder {
        let store = DebugRawAPIResponseUserDefaultsStore()
        return DebugRawAPIResponseRecorder(
            isEnabled: {
                UserDefaults.standard.bool(forKey: DebugRawAPIResponseSettings.isEnabledKey)
            },
            record: { response in
                await store.save(response)
            }
        )
    }
}
#endif
