import XCTest
@testable import WordScene

final class LanguageDirectionTests: XCTestCase {
    func testLanguageSelectionSupportsConfiguredTranslationLanguages() {
        let expectedTargets: [LanguageSelection] = [
            .zh,
            .zhHant,
            .en,
            .es,
            .fr,
            .de,
            .pt,
            .it,
            .ru,
            .ja,
            .ko,
            .nl,
            .pl,
            .ar,
            .tr,
            .vi,
            .indonesian,
            .hi
        ]

        XCTAssertEqual(LanguageSelection.sourceOptions, [.auto] + expectedTargets)
        XCTAssertEqual(LanguageSelection.targetOptions(excluding: .auto), expectedTargets)
        XCTAssertEqual(
            LanguageSelection.targetOptions(excluding: .zh),
            expectedTargets.filter { $0 != .zh }
        )
    }

    func testChineseLanguageTitlesDistinguishSimplifiedAndTraditional() {
        XCTAssertNotEqual(LanguageSelection.zh.title, LanguageSelection.zhHant.title)
        XCTAssertTrue(LanguageSelection.zh.title.contains("简体") || LanguageSelection.zh.title.contains("Simplified"))
        XCTAssertTrue(LanguageSelection.zhHant.title.contains("繁体") || LanguageSelection.zhHant.title.contains("Traditional"))
        XCTAssertNotEqual(LanguageSelection.zh.title, "中文")
        XCTAssertNotEqual(LanguageSelection.zh.title, "Chinese")
    }

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

    func testNormalizingConcreteSameLanguageDirectionChoosesDifferentTarget() {
        let direction = TranslationLanguageDirection(source: .zh, target: .zh)

        let normalized = direction.normalized()

        XCTAssertEqual(normalized.source, .zh)
        XCTAssertEqual(normalized.target, .en)
    }

    func testNormalizingValidDirectionKeepsCurrentTarget() {
        let direction = TranslationLanguageDirection(source: .en, target: .zh)

        XCTAssertEqual(direction.normalized(), direction)
    }
}
