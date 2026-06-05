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

    func testAcceptingClipboardTextUsesAutomaticSourceAndConfiguredTarget() throws {
        let prompt = try XCTUnwrap(
            TranslationClipboardPrompt.make(
                clipboardText: "Hola mundo",
                currentInput: "",
                dismissedText: nil
            )
        )

        let action = prompt.acceptance(defaultTargetLanguage: .en)

        XCTAssertEqual(action.inputText, "Hola mundo")
        XCTAssertEqual(action.sourceLanguage, .auto)
        XCTAssertEqual(action.targetLanguage, .en)
    }
}
