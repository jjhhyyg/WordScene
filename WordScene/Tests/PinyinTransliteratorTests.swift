import XCTest
@testable import WordScene

final class PinyinTransliteratorTests: XCTestCase {
    func testGeneratesSearchTermsForChineseText() {
        let transliterator = AppleSystemPinyinTransliterator()

        let terms = transliterator.indexTerms(for: "一个")

        XCTAssertEqual(terms.fullWithSpaces, "yi ge")
        XCTAssertEqual(terms.fullCompact, "yige")
        XCTAssertEqual(terms.initials, "yg")
    }
}
