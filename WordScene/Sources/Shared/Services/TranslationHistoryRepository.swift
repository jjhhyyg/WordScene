import Foundation

protocol TranslationHistoryDataStore {
    func load() -> [TranslationRecord]
    func save(_ records: [TranslationRecord])
    func loadOrThrow() throws -> [TranslationRecord]
    func saveOrThrow(_ records: [TranslationRecord]) throws
    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord]
}

struct TranslationHistoryRepository: TranslationHistoryDataStore {
    private let coreDataStore: (any CoreDataTranslationHistoryDataStore)?
    private let legacyStore: TranslationHistoryStore
    private let maximumCount: Int

    init(
        coreDataStore: (any CoreDataTranslationHistoryDataStore)? = try? CoreDataMemoryStore(),
        legacyStore: TranslationHistoryStore = TranslationHistoryStore(),
        maximumCount: Int = 50
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
    }

    func load() -> [TranslationRecord] {
        (try? loadOrThrow()) ?? legacyStore.load()
    }

    func loadOrThrow() throws -> [TranslationRecord] {
        guard let coreDataStore else {
            return legacyStore.load()
        }

        try migrateLegacyRecordsIfNeeded(into: coreDataStore)
        return try loadRecentRecords(from: coreDataStore)
    }

    func save(_ records: [TranslationRecord]) {
        do {
            try saveOrThrow(records)
        } catch {
            legacyStore.save(records)
        }
    }

    func saveOrThrow(_ records: [TranslationRecord]) throws {
        guard let coreDataStore else {
            legacyStore.save(records)
            return
        }

        try migrateLegacyRecordsIfNeeded(into: coreDataStore)
        try coreDataStore.replaceHistoryRecords(Array(records.prefix(maximumCount)))
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        Array(([record] + records).prefix(maximumCount))
    }

    private func migrateLegacyRecordsIfNeeded(into coreDataStore: any CoreDataTranslationHistoryDataStore) throws {
        let legacyRecords = legacyStore.load()
        guard !legacyRecords.isEmpty else {
            return
        }

        try coreDataStore.replaceHistoryRecords(Array(legacyRecords.prefix(maximumCount)))
        legacyStore.clear()
    }

    private func loadRecentRecords(from coreDataStore: any CoreDataTranslationHistoryDataStore) throws -> [TranslationRecord] {
        let records = try coreDataStore.loadHistoryRecords()
        return Array(records.prefix(maximumCount))
    }
}
