import Foundation

protocol MemoryLibraryDataStore {
    func load() -> [MemoryItem]
    func save(_ items: [MemoryItem])
    func loadOrThrow() throws -> [MemoryItem]
    func saveOrThrow(_ items: [MemoryItem]) throws
}

struct MemoryLibraryRepository: MemoryLibraryDataStore {
    private let coreDataStore: (any CoreDataMemoryDataStore)?
    private let legacyStore: MemoryLibraryStore
    private let maximumCount: Int

    init(
        coreDataStore: (any CoreDataMemoryDataStore)? = try? CoreDataMemoryStore(),
        legacyStore: MemoryLibraryStore = MemoryLibraryStore(),
        maximumCount: Int = 500
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
    }

    func load() -> [MemoryItem] {
        (try? loadOrThrow()) ?? legacyStore.load()
    }

    func loadOrThrow() throws -> [MemoryItem] {
        guard let coreDataStore else {
            return try legacyStore.loadOrThrow()
        }

        try migrateLegacyItemsIfNeeded(into: coreDataStore)
        return try loadActiveItems(from: coreDataStore)
    }

    func save(_ items: [MemoryItem]) {
        do {
            try saveOrThrow(items)
        } catch {
            legacyStore.save(items)
        }
    }

    func saveOrThrow(_ items: [MemoryItem]) throws {
        guard let coreDataStore else {
            legacyStore.save(items)
            return
        }

        try migrateLegacyItemsIfNeeded(into: coreDataStore)

        let replacementItems = Array(items.prefix(maximumCount))
        let replacementIDs = Set(replacementItems.map(\.id))
        let currentItems = try loadActiveItems(from: coreDataStore)

        for currentItem in currentItems where !replacementIDs.contains(currentItem.id) {
            try coreDataStore.softDelete(id: currentItem.id)
        }

        for item in replacementItems {
            try coreDataStore.upsert(item)
        }
    }

    func item(matching record: TranslationRecord, in items: [MemoryItem]) -> MemoryItem? {
        legacyStore.item(matching: record, in: items)
    }

    func adding(_ record: TranslationRecord, to items: [MemoryItem], note: String = "") -> [MemoryItem] {
        legacyStore.adding(record, to: items, note: note)
    }

    func removing(_ record: TranslationRecord, from items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.removing(record, from: items)
    }

    func removing(id: UUID, from items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.removing(id: id, from: items)
    }

    func updatingNote(for id: UUID, note: String, in items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.updatingNote(for: id, note: note, in: items)
    }

    private func migrateLegacyItemsIfNeeded(into coreDataStore: any CoreDataMemoryDataStore) throws {
        let legacyItems = try legacyStore.loadOrThrow()
        guard !legacyItems.isEmpty else {
            return
        }

        for item in legacyItems.prefix(maximumCount) {
            try coreDataStore.upsert(item)
        }
        legacyStore.clear()
    }

    private func loadActiveItems(from coreDataStore: any CoreDataMemoryDataStore) throws -> [MemoryItem] {
        let items = try coreDataStore.loadActiveItems()
        return Array(items.prefix(maximumCount))
    }
}
