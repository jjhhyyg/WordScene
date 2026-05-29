import Foundation

struct MemorySearchIndex {
    private let transliterator: PinyinTransliterating

    init(transliterator: PinyinTransliterating = AppleSystemPinyinTransliterator()) {
        self.transliterator = transliterator
    }

    func search(query: String, memoryItems: [MemoryItem], history: [TranslationRecord]) -> [MemorySearchResult] {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return []
        }

        var seenKeys = Set<MemorySearchKey>()
        var results: [MemorySearchResult] = []

        for item in memoryItems where matches(item: item, query: normalizedQuery) {
            seenKeys.insert(MemorySearchKey(item: item))
            results.append(MemorySearchResult(item: item))
        }

        for record in history where matches(record: record, query: normalizedQuery) {
            let key = MemorySearchKey(record: record)
            guard !seenKeys.contains(key) else {
                continue
            }

            seenKeys.insert(key)
            results.append(MemorySearchResult(record: record))
        }

        return results
    }

    private func matches(item: MemoryItem, query: String) -> Bool {
        searchTerms(
            sourceText: item.sourceText,
            translatedText: item.translatedText,
            sourceLanguage: item.sourceLanguage,
            targetLanguage: item.targetLanguage,
            note: item.note
        )
        .contains { $0.contains(query) }
    }

    private func matches(record: TranslationRecord, query: String) -> Bool {
        searchTerms(
            sourceText: record.sourceText,
            translatedText: record.translatedText,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            note: ""
        )
        .contains { $0.contains(query) }
    }

    private func searchTerms(
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        note: String
    ) -> [String] {
        var terms = [
            sourceText,
            translatedText,
            sourceLanguage.title,
            targetLanguage.title,
            sourceLanguage.rawValue,
            targetLanguage.rawValue,
            note
        ]

        terms.append(contentsOf: pinyinTerms(for: sourceText))
        terms.append(contentsOf: pinyinTerms(for: translatedText))
        terms.append(contentsOf: pinyinTerms(for: note))

        return terms
            .map(Self.normalized)
            .filter { !$0.isEmpty }
    }

    private func pinyinTerms(for text: String) -> [String] {
        let terms = transliterator.indexTerms(for: text)
        return [terms.fullWithSpaces, terms.fullCompact, terms.initials]
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct MemorySearchResult: Identifiable, Equatable {
    enum Kind: Equatable {
        case memory
        case history
    }

    let id: String
    let kind: Kind
    let sourceText: String
    let translatedText: String
    let sourceLanguage: LanguageSelection
    let targetLanguage: LanguageSelection
    let note: String
    let createdAt: Date

    init(item: MemoryItem) {
        self.id = "memory-\(item.id.uuidString)"
        self.kind = .memory
        self.sourceText = item.sourceText
        self.translatedText = item.translatedText
        self.sourceLanguage = item.sourceLanguage
        self.targetLanguage = item.targetLanguage
        self.note = item.note
        self.createdAt = item.createdAt
    }

    init(record: TranslationRecord) {
        self.id = "history-\(record.id.uuidString)"
        self.kind = .history
        self.sourceText = record.sourceText
        self.translatedText = record.translatedText
        self.sourceLanguage = record.sourceLanguage
        self.targetLanguage = record.targetLanguage
        self.note = ""
        self.createdAt = record.createdAt
    }
}

private struct MemorySearchKey: Hashable {
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

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
