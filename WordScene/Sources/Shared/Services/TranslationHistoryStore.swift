import Foundation

struct TranslationHistoryStore {
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

        return (try? JSONDecoder().decode([TranslationRecord].self, from: data)) ?? []
    }

    func save(_ records: [TranslationRecord]) {
        let trimmedRecords = Array(records.prefix(maximumCount))
        guard let data = try? JSONEncoder().encode(trimmedRecords) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        Array(([record] + records).prefix(maximumCount))
    }
}
