import XCTest
@testable import WordScene

final class MemoryItemCodingTests: XCTestCase {
    func testDisplaySourceLanguageResolvesLegacyAutoSourceFromSourceText() {
        let item = MemoryItem(
            sourceText: "hello",
            translatedText: "你好",
            sourceLanguage: .auto,
            targetLanguage: .zh
        )

        XCTAssertEqual(item.displaySourceLanguage, .en)
    }

    func testDisplaySourceLanguageResolvesLegacyAutoSpanishSourceFromSourceText() {
        let item = MemoryItem(
            sourceText: "Hola",
            translatedText: "你好",
            sourceLanguage: .auto,
            targetLanguage: .zh
        )

        XCTAssertEqual(item.displaySourceLanguage, .es)
    }

    func testMemoryItemFromAutoRecordStoresResolvedSpanishSourceLanguage() {
        let record = TranslationRecord(
            sourceText: "Hola",
            translatedText: "你好",
            sourceLanguage: .auto,
            targetLanguage: .zh
        )

        let item = MemoryItem(record: record)

        XCTAssertEqual(item.sourceLanguage, .es)
    }

    func testDecodingLegacyJSONWithoutStarredDefaultsToFalse() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "sourceText": "hello",
          "translatedText": "你好",
          "sourceLanguage": "en",
          "targetLanguage": "zh",
          "note": "legacy",
          "createdAt": 10,
          "updatedAt": 20
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(MemoryItem.self, from: json)

        XCTAssertFalse(item.isStarred)
    }
}
