import Foundation

struct MemoryLibraryStore: MemoryLibraryDataStore {
    private static let schemaVersion = 1

    private let defaults: UserDefaults
    private let key: String
    private let maximumCount: Int

    init(
        defaults: UserDefaults = .standard,
        key: String = "memoryLibrary",
        maximumCount: Int = 500
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumCount = maximumCount
    }

    func load() -> [MemoryItem] {
        (try? loadOrThrow()) ?? []
    }

    func loadOrThrow() throws -> [MemoryItem] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        let decoder = JSONDecoder()
        if let document = try? decoder.decode(MemoryLibraryDocument.self, from: data) {
            guard document.schemaVersion == Self.schemaVersion else {
                throw LocalPersistenceStoreError.unsupportedSchemaVersion(
                    key: key,
                    version: document.schemaVersion
                )
            }
            return Array(document.items.prefix(maximumCount))
        }

        if let legacyItems = try? decoder.decode([MemoryItem].self, from: data) {
            let trimmedItems = Array(legacyItems.prefix(maximumCount))
            save(trimmedItems)
            return trimmedItems
        }

        throw LocalPersistenceStoreError.unreadableDocument(key: key)
    }

    func save(_ items: [MemoryItem]) {
        let trimmedItems = Array(items.prefix(maximumCount))
        let document = MemoryLibraryDocument(
            schemaVersion: Self.schemaVersion,
            items: trimmedItems
        )
        guard let data = try? JSONEncoder().encode(document) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func saveOrThrow(_ items: [MemoryItem]) throws {
        save(items)
    }

    func deleteOrThrow(id: UUID) throws {
        let currentItems = try loadOrThrow()
        save(removing(id: id, from: currentItems))
    }

    func deleteAllOrThrow() throws {
        save([])
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func item(matching record: TranslationRecord, in items: [MemoryItem]) -> MemoryItem? {
        let recordKey = MemoryMatchKey(record: record)
        return items.first { MemoryMatchKey(item: $0) == recordKey }
    }

    func adding(_ record: TranslationRecord, to items: [MemoryItem], note: String = "") -> [MemoryItem] {
        let newItem = MemoryItem(record: record, note: note)
        let newItemKey = MemoryMatchKey(item: newItem)
        let withoutDuplicate = items.filter { MemoryMatchKey(item: $0) != newItemKey }
        return Array(([newItem] + withoutDuplicate).prefix(maximumCount))
    }

    func adding(_ item: MemoryItem, to items: [MemoryItem]) -> [MemoryItem] {
        var newItem = item
        newItem.sourceText = item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem.translatedText = item.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        newItem.note = item.note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newItem.sourceText.isEmpty, !newItem.translatedText.isEmpty else {
            return items
        }

        let newItemKey = MemoryMatchKey(item: newItem)
        let withoutDuplicate = items.filter { MemoryMatchKey(item: $0) != newItemKey }
        return Array(([newItem] + withoutDuplicate).prefix(maximumCount))
    }

    func removing(_ record: TranslationRecord, from items: [MemoryItem]) -> [MemoryItem] {
        let recordKey = MemoryMatchKey(record: record)
        return items.filter { MemoryMatchKey(item: $0) != recordKey }
    }

    func removing(id: UUID, from items: [MemoryItem]) -> [MemoryItem] {
        items.filter { $0.id != id }
    }

    func updatingNote(for id: UUID, note: String, in items: [MemoryItem]) -> [MemoryItem] {
        items.map { item in
            guard item.id == id else {
                return item
            }

            var updatedItem = item
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard updatedItem.note != trimmedNote else {
                return item
            }
            updatedItem.note = trimmedNote
            updatedItem.updatedAt = Date()
            return updatedItem
        }
    }

    func updatingItem(_ replacement: MemoryItem, in items: [MemoryItem]) -> [MemoryItem] {
        let trimmedSource = replacement.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslation = replacement.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedTranslation.isEmpty else {
            return items
        }

        return items.map { item in
            guard item.id == replacement.id else {
                return item
            }

            var updatedItem = item
            updatedItem.sourceText = trimmedSource
            updatedItem.translatedText = trimmedTranslation
            updatedItem.sourceLanguage = replacement.sourceLanguage
            updatedItem.targetLanguage = replacement.targetLanguage
            updatedItem.note = replacement.note.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedItem.isStarred = replacement.isStarred
            guard updatedItem != item else {
                return item
            }
            updatedItem.updatedAt = Date()
            return updatedItem
        }
    }

    func updatingStar(for id: UUID, isStarred: Bool, in items: [MemoryItem]) -> [MemoryItem] {
        items.map { item in
            guard item.id == id, item.isStarred != isStarred else {
                return item
            }
            var updatedItem = item
            updatedItem.isStarred = isStarred
            updatedItem.updatedAt = Date()
            return updatedItem
        }
    }
}

private struct MemoryLibraryDocument: Codable {
    let schemaVersion: Int
    let items: [MemoryItem]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case items
    }
}

private struct MemoryMatchKey: Equatable {
    let sourceText: String
    let translatedText: String
    let sourceLanguage: LanguageSelection
    let targetLanguage: LanguageSelection

    init(item: MemoryItem) {
        self.sourceText = Self.normalized(item.sourceText)
        self.translatedText = Self.normalized(item.translatedText)
        self.sourceLanguage = item.sourceLanguage
        self.targetLanguage = item.targetLanguage
    }

    init(record: TranslationRecord) {
        self.sourceText = Self.normalized(record.sourceText)
        self.translatedText = Self.normalized(record.translatedText)
        self.sourceLanguage = record.sourceLanguage
        self.targetLanguage = record.targetLanguage
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
