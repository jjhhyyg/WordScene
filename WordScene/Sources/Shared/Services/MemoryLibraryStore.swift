import Foundation

struct MemoryLibraryStore {
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
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        return (try? JSONDecoder().decode([MemoryItem].self, from: data)) ?? []
    }

    func save(_ items: [MemoryItem]) {
        let trimmedItems = Array(items.prefix(maximumCount))
        guard let data = try? JSONEncoder().encode(trimmedItems) else {
            return
        }

        defaults.set(data, forKey: key)
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
            updatedItem.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedItem.updatedAt = Date()
            return updatedItem
        }
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
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
