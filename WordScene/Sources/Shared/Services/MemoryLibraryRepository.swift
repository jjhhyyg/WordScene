import Foundation

protocol MemoryLibraryDataStore {
    func load() -> [MemoryItem]
    func save(_ items: [MemoryItem])
}

struct MemoryLibraryRepository: MemoryLibraryDataStore {
    private let coreDataStore: CoreDataMemoryStore?
    private let legacyStore: MemoryLibraryStore
    private let maximumCount: Int

    init(
        coreDataStore: CoreDataMemoryStore? = try? CoreDataMemoryStore(),
        legacyStore: MemoryLibraryStore = MemoryLibraryStore(),
        maximumCount: Int = 500
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
    }

    func load() -> [MemoryItem] {
        guard let coreDataStore else {
            return legacyStore.load()
        }

        migrateLegacyItemsIfNeeded(into: coreDataStore)
        return loadActiveItems(from: coreDataStore)
    }

    func save(_ items: [MemoryItem]) {
        guard let coreDataStore else {
            legacyStore.save(items)
            return
        }

        migrateLegacyItemsIfNeeded(into: coreDataStore)

        let replacementItems = Array(items.prefix(maximumCount))
        let replacementIDs = Set(replacementItems.map(\.id))
        let currentItems = loadActiveItems(from: coreDataStore)

        for currentItem in currentItems where !replacementIDs.contains(currentItem.id) {
            try? coreDataStore.softDelete(id: currentItem.id)
        }

        for item in replacementItems {
            try? coreDataStore.upsert(item)
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

    private func migrateLegacyItemsIfNeeded(into coreDataStore: CoreDataMemoryStore) {
        let legacyItems = legacyStore.load()
        guard !legacyItems.isEmpty else {
            return
        }

        for item in legacyItems.prefix(maximumCount) {
            try? coreDataStore.upsert(item)
        }
        legacyStore.clear()
    }

    private func loadActiveItems(from coreDataStore: CoreDataMemoryStore) -> [MemoryItem] {
        guard let items = try? coreDataStore.loadActiveItems() else {
            return legacyStore.load()
        }

        return Array(items.prefix(maximumCount))
    }
}
