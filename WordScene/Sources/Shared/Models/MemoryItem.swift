import Foundation

struct MemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceText: String
    var translatedText: String
    var sourceLanguage: LanguageSelection
    var targetLanguage: LanguageSelection
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var isStarred: Bool

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isStarred: Bool = false
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isStarred = isStarred
    }

    init(record: TranslationRecord, note: String = "", createdAt: Date = Date()) {
        self.init(
            sourceText: record.sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            translatedText: record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: record.resolvedSourceLanguage,
            targetLanguage: record.targetLanguage,
            note: note,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sourceText
        case translatedText
        case sourceLanguage
        case targetLanguage
        case note
        case createdAt
        case updatedAt
        case isStarred
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.sourceText = try container.decode(String.self, forKey: .sourceText)
        self.translatedText = try container.decode(String.self, forKey: .translatedText)
        self.sourceLanguage = try container.decode(LanguageSelection.self, forKey: .sourceLanguage)
        self.targetLanguage = try container.decode(LanguageSelection.self, forKey: .targetLanguage)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isStarred = try container.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }
}

extension MemoryItem {
    var displaySourceLanguage: LanguageSelection {
        guard sourceLanguage == .auto else {
            return sourceLanguage
        }
        return TranslationLanguageDetector.detect(sourceText) ?? sourceLanguage
    }
}

extension TranslationRecord {
    var resolvedSourceLanguage: LanguageSelection {
        guard sourceLanguage == .auto else {
            return sourceLanguage
        }
        return TranslationLanguageDetector.detect(sourceText) ?? sourceLanguage
    }
}
