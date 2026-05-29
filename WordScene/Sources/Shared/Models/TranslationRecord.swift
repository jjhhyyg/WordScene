import Foundation

struct TranslationRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguage: LanguageSelection
    let targetLanguage: LanguageSelection
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguage: LanguageSelection,
        targetLanguage: LanguageSelection,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}
