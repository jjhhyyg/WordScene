import XCTest
@testable import WordScene

final class MemoryItemCodingTests: XCTestCase {
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
