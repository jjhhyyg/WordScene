import Foundation

protocol TranslationHistoryDataStore {
    func load() -> [TranslationRecord]
    func save(_ records: [TranslationRecord])
    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord]
}

struct TranslationHistoryRepository: TranslationHistoryDataStore {
    private let coreDataStore: CoreDataMemoryStore?
    private let legacyStore: TranslationHistoryStore
    private let maximumCount: Int

    init(
        coreDataStore: CoreDataMemoryStore? = try? CoreDataMemoryStore(),
        legacyStore: TranslationHistoryStore = TranslationHistoryStore(),
        maximumCount: Int = 50
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
    }

    func load() -> [TranslationRecord] {
        guard let coreDataStore else {
            return legacyStore.load()
        }

        migrateLegacyRecordsIfNeeded(into: coreDataStore)
        return loadRecentRecords(from: coreDataStore)
    }

    func save(_ records: [TranslationRecord]) {
        guard let coreDataStore else {
            legacyStore.save(records)
            return
        }

        migrateLegacyRecordsIfNeeded(into: coreDataStore)
        try? coreDataStore.replaceHistoryRecords(Array(records.prefix(maximumCount)))
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        Array(([record] + records).prefix(maximumCount))
    }

    private func migrateLegacyRecordsIfNeeded(into coreDataStore: CoreDataMemoryStore) {
        let legacyRecords = legacyStore.load()
        guard !legacyRecords.isEmpty else {
            return
        }

        do {
            try coreDataStore.replaceHistoryRecords(Array(legacyRecords.prefix(maximumCount)))
            legacyStore.clear()
        } catch {
            return
        }
    }

    private func loadRecentRecords(from coreDataStore: CoreDataMemoryStore) -> [TranslationRecord] {
        guard let records = try? coreDataStore.loadHistoryRecords() else {
            return legacyStore.load()
        }

        return Array(records.prefix(maximumCount))
    }
}
