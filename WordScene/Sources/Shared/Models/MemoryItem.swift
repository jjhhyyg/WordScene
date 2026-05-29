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

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(record: TranslationRecord, note: String = "", createdAt: Date = Date()) {
        self.init(
            sourceText: record.sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
            translatedText: record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            note: note,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
