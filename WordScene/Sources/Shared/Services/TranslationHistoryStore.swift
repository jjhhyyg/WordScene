import Foundation

struct TranslationHistoryStore {
    private static let schemaVersion = 1

    private let defaults: UserDefaults
    private let key: String
    private let maximumCount: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = "translationHistory",
        maximumCount: Int = 50
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumCount = maximumCount
    }

    func load() -> [TranslationRecord] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        let decoder = JSONDecoder()
        if let document = try? decoder.decode(TranslationHistoryDocument.self, from: data) {
            return Array(document.records.prefix(maximumCount))
        }

        if let legacyRecords = try? decoder.decode([TranslationRecord].self, from: data) {
            let trimmedRecords = Array(legacyRecords.prefix(maximumCount))
            save(trimmedRecords)
            return trimmedRecords
        }

        return []
    }

    func save(_ records: [TranslationRecord]) {
        let trimmedRecords = Array(records.prefix(maximumCount))
        let document = TranslationHistoryDocument(
            schemaVersion: Self.schemaVersion,
            records: trimmedRecords
        )
        guard let data = try? JSONEncoder().encode(document) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        Array(([record] + records).prefix(maximumCount))
    }
}

private struct TranslationHistoryDocument: Codable {
    let schemaVersion: Int
    let records: [TranslationRecord]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case records
    }
}
