import Foundation

struct TranslationHistoryStore: TranslationHistoryDataStore {
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
        (try? loadOrThrow()) ?? []
    }

    func loadOrThrow() throws -> [TranslationRecord] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        let decoder = JSONDecoder()
        if let document = try? decoder.decode(TranslationHistoryDocument.self, from: data) {
            guard document.schemaVersion == Self.schemaVersion else {
                throw LocalPersistenceStoreError.unsupportedSchemaVersion(
                    key: key,
                    version: document.schemaVersion
                )
            }
            return Array(document.records.prefix(maximumCount))
        }

        if let legacyRecords = try? decoder.decode([TranslationRecord].self, from: data) {
            let trimmedRecords = Array(legacyRecords.prefix(maximumCount))
            save(trimmedRecords)
            return trimmedRecords
        }

        throw LocalPersistenceStoreError.unreadableDocument(key: key)
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

    func saveOrThrow(_ records: [TranslationRecord]) throws {
        save(records)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        let deduplicatedRecords = records.filter { !$0.hasSameTranslationContent(as: record) }
        return Array(([record] + deduplicatedRecords).prefix(maximumCount))
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
