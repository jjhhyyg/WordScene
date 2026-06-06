import XCTest
@testable import WordScene

final class TranslationClipboardPromptTests: XCTestCase {
    func testEmptyClipboardDoesNotPrompt() {
        XCTAssertNil(
            TranslationClipboardPrompt.make(
                clipboardText: "   \n",
                currentInput: "",
                dismissedText: nil
            )
        )
    }

    func testValidClipboardTextPrompts() throws {
        let prompt = try XCTUnwrap(
            TranslationClipboardPrompt.make(
                clipboardText: "  Hola mundo  ",
                currentInput: "",
                dismissedText: nil
            )
        )

        XCTAssertEqual(prompt.text, "Hola mundo")
    }

    func testMatchingCurrentInputDoesNotPrompt() {
        XCTAssertNil(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: " Hola mundo ",
                dismissedText: nil
            )
        )
    }

    func testDismissedClipboardTextDoesNotPromptAgain() {
        XCTAssertNil(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: "",
                dismissedText: "Hola mundo"
            )
        )
    }

    func testDismissedClipboardTextIgnoresSurroundingWhitespace() {
        XCTAssertNil(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: "",
                dismissedText: "  Hola mundo\n"
            )
        )
    }

    func testAcceptingClipboardTextUsesCurrentTranslationPageDirection() throws {
        let prompt = try XCTUnwrap(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: "",
                dismissedText: nil
            )
        )

        let action = prompt.acceptance(currentSourceLanguage: .es, currentTargetLanguage: .en)

        XCTAssertEqual(action.inputText, "Hola mundo")
        XCTAssertEqual(action.sourceLanguage, .es)
        XCTAssertEqual(action.targetLanguage, .en)
    }

    func testAcceptingClipboardTextNormalizesInvalidCurrentDirection() throws {
        let prompt = try XCTUnwrap(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: "",
                dismissedText: nil
            )
        )

        let action = prompt.acceptance(currentSourceLanguage: .en, currentTargetLanguage: .en)

        XCTAssertEqual(action.inputText, "Hola mundo")
        XCTAssertEqual(action.sourceLanguage, .en)
        XCTAssertEqual(action.targetLanguage, .zh)
    }
}
