import Foundation

protocol MemoryLibraryDataStore {
    func load() -> [MemoryItem]
    func save(_ items: [MemoryItem])
    func loadOrThrow() throws -> [MemoryItem]
    func saveOrThrow(_ items: [MemoryItem]) throws
    func deleteOrThrow(id: UUID) throws
    func deleteAllOrThrow() throws
}

protocol MemoryLibraryDeletionTombstoneProviding {
    func loadDeletionTombstones() throws -> [CoreDataDeletionTombstone]
}

enum TombstoneRetentionPolicy: Equatable {
    case localOnly(days: Int)
    case cloudKit(days: Int, requiresSuccessfulExport: Bool)

    func cutoffDate(now: Date = Date()) -> Date {
        let days: Int
        switch self {
        case .localOnly(let value), .cloudKit(let value, _):
            days = value
        }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? now
    }
}

struct MemoryLibraryRepository: MemoryLibraryDataStore, MemoryLibraryDeletionTombstoneProviding {
    private let coreDataStore: (any CoreDataMemoryDataStore)?
    private let legacyStore: MemoryLibraryStore
    private let maximumCount: Int
    private let changeRecorder: () -> Void

    init(
        coreDataStore: (any CoreDataMemoryDataStore)? = try? CoreDataMemoryStore(),
        legacyStore: MemoryLibraryStore = MemoryLibraryStore(),
        maximumCount: Int = 500,
        changeRecorder: @escaping () -> Void = {}
    ) {
        self.coreDataStore = coreDataStore
        self.legacyStore = legacyStore
        self.maximumCount = maximumCount
        self.changeRecorder = changeRecorder
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
            changeRecorder()
        }
    }

    func saveOrThrow(_ items: [MemoryItem]) throws {
        let replacementItems = Array(items.prefix(maximumCount))
        guard let coreDataStore else {
            if (try? legacyStore.loadOrThrow()) == replacementItems {
                return
            }
            legacyStore.save(replacementItems)
            changeRecorder()
            return
        }

        try migrateLegacyItemsIfNeeded(into: coreDataStore)

        let replacementIDs = Set(replacementItems.map(\.id))
        let currentItems = try loadActiveItems(from: coreDataStore)
        guard currentItems != replacementItems else {
            return
        }

        for currentItem in currentItems where !replacementIDs.contains(currentItem.id) {
            try coreDataStore.softDelete(id: currentItem.id)
        }

        for item in replacementItems {
            try coreDataStore.upsert(item)
        }
        changeRecorder()
    }

    func deleteOrThrow(id: UUID) throws {
        guard let coreDataStore else {
            let currentItems = try legacyStore.loadOrThrow()
            let replacementItems = legacyStore.removing(id: id, from: currentItems)
            guard currentItems != replacementItems else {
                return
            }
            try legacyStore.saveOrThrow(replacementItems)
            changeRecorder()
            return
        }

        try migrateLegacyItemsIfNeeded(into: coreDataStore)
        let currentItems = try loadActiveItems(from: coreDataStore)
        guard currentItems.contains(where: { $0.id == id }) else {
            return
        }
        try coreDataStore.softDelete(id: id)
        changeRecorder()
    }

    func deleteAllOrThrow() throws {
        guard let coreDataStore else {
            let currentItems = try legacyStore.loadOrThrow()
            guard !currentItems.isEmpty else {
                return
            }
            try legacyStore.saveOrThrow([])
            changeRecorder()
            return
        }

        try migrateLegacyItemsIfNeeded(into: coreDataStore)
        let currentItems = try loadActiveItems(from: coreDataStore)
        guard !currentItems.isEmpty else {
            return
        }

        for item in currentItems {
            try coreDataStore.softDelete(id: item.id)
        }
        changeRecorder()
    }

    func toggleStarOrThrow(id: UUID) throws -> MemoryItem? {
        var currentItems = try loadOrThrow()
        guard let index = currentItems.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        currentItems[index].isStarred.toggle()
        currentItems[index].updatedAt = Date()
        try saveOrThrow(currentItems)
        return currentItems[index]
    }

    func loadDeletionTombstones() throws -> [CoreDataDeletionTombstone] {
        guard let coreDataStore else {
            return []
        }

        return try coreDataStore.loadDeletionTombstones()
    }

    func purgeExpiredDeletionTombstones(
        policy: TombstoneRetentionPolicy,
        now: Date = Date()
    ) throws -> Int {
        guard let coreDataStore else {
            return 0
        }

        return try coreDataStore.purgeDeletedItemsAndTombstones(
            olderThan: policy.cutoffDate(now: now)
        )
    }

    func item(matching record: TranslationRecord, in items: [MemoryItem]) -> MemoryItem? {
        legacyStore.item(matching: record, in: items)
    }

    func adding(_ record: TranslationRecord, to items: [MemoryItem], note: String = "") -> [MemoryItem] {
        legacyStore.adding(record, to: items, note: note)
    }

    func adding(_ item: MemoryItem, to items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.adding(item, to: items)
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

    func updatingItem(_ replacement: MemoryItem, in items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.updatingItem(replacement, in: items)
    }

    func updatingStar(for id: UUID, isStarred: Bool, in items: [MemoryItem]) -> [MemoryItem] {
        legacyStore.updatingStar(for: id, isStarred: isStarred, in: items)
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
