import XCTest
@testable import WordScene

final class MemorySearchIndexTests: XCTestCase {
    func testMatchesSavedMemoryByOriginalTranslationNoteAndLanguage() {
        let index = MemorySearchIndex(transliterator: StubPinyinTransliterator())
        let item = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .en,
            targetLanguage: .zh,
            note: "greeting phrase"
        )

        XCTAssertEqual(index.search(query: "hello", memoryItems: [item], history: []).map(\.sourceText), ["hello"])
        XCTAssertEqual(index.search(query: "你好", memoryItems: [item], history: []).map(\.sourceText), ["hello"])
        XCTAssertEqual(index.search(query: "greeting", memoryItems: [item], history: []).map(\.sourceText), ["hello"])
        XCTAssertEqual(index.search(query: "英文", memoryItems: [item], history: []).map(\.sourceText), ["hello"])
    }

    func testMatchesRecentHistoryWhenItemIsNotSaved() {
        let index = MemorySearchIndex(transliterator: StubPinyinTransliterator())
        let record = TranslationRecord(
            sourceText: "good night",
            translatedText: "晚安",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        let results = index.search(query: "night", memoryItems: [], history: [record])

        XCTAssertEqual(results.map(\.sourceText), ["good night"])
        XCTAssertEqual(results.first?.kind, .history)
    }

    func testSavedItemWinsOverDuplicateHistoryRecord() {
        let index = MemorySearchIndex(transliterator: StubPinyinTransliterator())
        let item = MemoryItem(
            sourceText: "cat",
            translatedText: "猫",
            sourceLanguage: .en,
            targetLanguage: .zh
        )
        let record = TranslationRecord(
            sourceText: "cat",
            translatedText: "猫",
            sourceLanguage: .en,
            targetLanguage: .zh
        )

        let results = index.search(query: "cat", memoryItems: [item], history: [record])

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.kind, .memory)
    }

    func testMatchesChineseTextByCompactPinyinAndInitials() {
        let index = MemorySearchIndex(transliterator: StubPinyinTransliterator())
        let item = MemoryItem(
            sourceText: "一个",
            translatedText: "one",
            sourceLanguage: .zh,
            targetLanguage: .en
        )

        XCTAssertEqual(index.search(query: "yige", memoryItems: [item], history: []).map(\.sourceText), ["一个"])
        XCTAssertEqual(index.search(query: "yg", memoryItems: [item], history: []).map(\.sourceText), ["一个"])
    }

    func testBlankQueryReturnsNoResults() {
        let index = MemorySearchIndex(transliterator: StubPinyinTransliterator())
        let item = MemoryItem(sourceText: "hello", translatedText: "你好", sourceLanguage: .en, targetLanguage: .zh)

        XCTAssertTrue(index.search(query: "   ", memoryItems: [item], history: []).isEmpty)
    }
}

private struct StubPinyinTransliterator: PinyinTransliterating {
    func indexTerms(for text: String) -> PinyinIndexTerms {
        if text.contains("一个") {
            return PinyinIndexTerms(fullWithSpaces: "yi ge", fullCompact: "yige", initials: "yg")
        }

        return PinyinIndexTerms(fullWithSpaces: "", fullCompact: "", initials: "")
    }
}
