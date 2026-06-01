import Foundation

protocol TranslationHistoryDataStore {
    func load() -> [TranslationRecord]
    func save(_ records: [TranslationRecord])
    func loadOrThrow() throws -> [TranslationRecord]
    func saveOrThrow(_ records: [TranslationRecord]) throws
    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord]
    func removing(id: UUID, from records: [TranslationRecord]) -> [TranslationRecord]
    func deleteAllOrThrow() throws
}

struct TranslationHistoryRepository: TranslationHistoryDataStore {
    private let coreDataStore: (any CoreDataTranslationHistoryDataStore)?
    private let legacyStore: TranslationHistoryStore
    private let maximumCount: Int
    private let changeRecorder: () -> Void

    init(
        coreDataStore: (any CoreDataTranslationHistoryDataStore)? = try? CoreDataMemoryStore(),
        legacyStore: TranslationHistoryStore = TranslationHistoryStore(),
        maximumCount: Int = 100,
        changeRecorder: @escaping () -> Void = {}
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
        self.changeRecorder = changeRecorder
    }

    func load() -> [TranslationRecord] {
        (try? loadOrThrow()) ?? legacyStore.load()
    }

    func loadOrThrow() throws -> [TranslationRecord] {
        guard let coreDataStore else {
            return try legacyStore.loadOrThrow()
        }

        try migrateLegacyRecordsIfNeeded(into: coreDataStore)
        return try loadRecentRecords(from: coreDataStore)
    }

    func save(_ records: [TranslationRecord]) {
        do {
            try saveOrThrow(records)
        } catch {
            legacyStore.save(records)
            changeRecorder()
        }
    }

    func saveOrThrow(_ records: [TranslationRecord]) throws {
        let replacementRecords = Array(records.prefix(maximumCount))
        guard let coreDataStore else {
            if (try? legacyStore.loadOrThrow()) == replacementRecords {
                return
            }
            legacyStore.save(replacementRecords)
            changeRecorder()
            return
        }

        try migrateLegacyRecordsIfNeeded(into: coreDataStore)
        let currentRecords = try loadRecentRecords(from: coreDataStore)
        guard currentRecords != replacementRecords else {
            return
        }
        try coreDataStore.replaceHistoryRecords(replacementRecords)
        changeRecorder()
    }

    func adding(_ record: TranslationRecord, to records: [TranslationRecord]) -> [TranslationRecord] {
        let deduplicatedRecords = records.filter { !$0.hasSameTranslationContent(as: record) }
        return Array(([record] + deduplicatedRecords).prefix(maximumCount))
    }

    func removing(id: UUID, from records: [TranslationRecord]) -> [TranslationRecord] {
        records.filter { $0.id != id }
    }

    func deleteAllOrThrow() throws {
        try saveOrThrow([])
    }

    private func migrateLegacyRecordsIfNeeded(into coreDataStore: any CoreDataTranslationHistoryDataStore) throws {
        let legacyRecords = try legacyStore.loadOrThrow()
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
