import XCTest
@testable import WordScene

final class LanguageDirectionTests: XCTestCase {
    func testAutoSourceCannotSwap() {
        let direction = TranslationLanguageDirection(source: .auto, target: .zh)

        let swapped = direction.swapped()

        XCTAssertFalse(direction.canSwap)
        XCTAssertEqual(swapped, direction)
    }

    func testSwappingConcreteLanguagesReversesDirection() {
        let direction = TranslationLanguageDirection(source: .zh, target: .en)

        let swapped = direction.swapped()

        XCTAssertEqual(swapped.source, .en)
        XCTAssertEqual(swapped.target, .zh)
    }
}
