import XCTest
#if os(macOS)
import AppKit
#endif

@MainActor
final class WordSceneLaunchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(
        seed: String? = nil,
        language: String? = "zh-Hans",
        locale: String? = "zh_CN",
        translationMode: String? = nil,
        translationInput: String? = nil,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        deepSeekToken: String? = nil,
        deepSeekTokenMode: String? = nil,
        memoryExportURL: URL? = nil,
        memoryImportURL: URL? = nil
    ) {
        app = XCUIApplication()
        app.launchArguments.append("-WordSceneUITest")
        #if !os(macOS)
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        if let locale {
            app.launchArguments += ["-AppleLocale", locale]
        }
        #endif
        app.launchEnvironment["WORDSCENE_UI_TEST_SUITE"] = "WordSceneUITests.\(UUID().uuidString)"
        if let seed {
            app.launchEnvironment["WORDSCENE_UI_TEST_SEED"] = seed
        }
        if let translationMode {
            app.launchEnvironment["WORDSCENE_UI_TEST_TRANSLATION_MODE"] = translationMode
        }
        if let translationInput {
            app.launchEnvironment["WORDSCENE_UI_TEST_TRANSLATION_INPUT"] = translationInput
        }
        if let sourceLanguage {
            app.launchEnvironment["WORDSCENE_UI_TEST_SOURCE_LANGUAGE"] = sourceLanguage
        }
        if let targetLanguage {
            app.launchEnvironment["WORDSCENE_UI_TEST_TARGET_LANGUAGE"] = targetLanguage
        }
        if let deepSeekToken {
            app.launchEnvironment["WORDSCENE_UI_TEST_DEEPSEEK_TOKEN"] = deepSeekToken
        }
        if let deepSeekTokenMode {
            app.launchEnvironment["WORDSCENE_UI_TEST_DEEPSEEK_TOKEN_MODE"] = deepSeekTokenMode
        }
        if let memoryExportURL {
            app.launchEnvironment["WORDSCENE_UI_TEST_MEMORY_EXPORT_URL"] = memoryExportURL.path
        }
        if let memoryImportURL {
            app.launchEnvironment["WORDSCENE_UI_TEST_MEMORY_IMPORT_URL"] = memoryImportURL.path
        }
        app.launch()
        #if os(macOS)
        app.activate()
        #endif
    }

    private func launchTranslationApp(translationMode: String, translationInput: String) {
        #if os(macOS)
        launchApp(translationMode: translationMode, translationInput: translationInput)
        #else
        launchApp(translationMode: translationMode)
        #endif
    }

    func testTranslateScreenInitialStateAndInputReadiness() throws {
        launchApp()

        let inputEditor = translationInputEditor()
        XCTAssertTrue(inputEditor.waitForExistence(timeout: 12))

        let startButton = app.buttons["translation.start"].firstMatch
        XCTAssertTrue(startButton.exists)
        XCTAssertFalse(startButton.isEnabled)

        let swapButton = app.buttons["translation.swapDirection"].firstMatch
        if swapButton.exists {
            XCTAssertFalse(swapButton.isEnabled)
        }

        #if os(macOS)
        return
        #else
        enterText("hello", into: inputEditor)

        XCTAssertTrue(startButton.waitForEnabled(timeout: 4))
        XCTAssertFalse(app.buttons["translation.clear"].firstMatch.exists)

        let inputClearButton = app.buttons["translation.input.clear"].firstMatch
        XCTAssertTrue(inputClearButton.waitForExistence(timeout: 4))
        activate(inputClearButton)
        XCTAssertTrue(startButton.waitForDisabled(timeout: 4))
        #endif
    }

    func testTappingOutsideTranslationInputDismissesKeyboard() throws {
        try XCTSkipIf(isMacUIRun, "Keyboard dismissal is covered by iOS and iPadOS UI tests.")
        launchApp()

        let inputEditor = translationInputEditor()
        XCTAssertTrue(inputEditor.waitForExistence(timeout: 12))

        enterText("hello", into: inputEditor)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let startButton = app.buttons["translation.start"].firstMatch
        XCTAssertTrue(startButton.waitForEnabled(timeout: 4))
        XCTAssertTrue(startButton.waitForHittable(timeout: 4))
    }

    func testExistingLibraryNoteRequiresEditBeforeSavingChanges() throws {
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded note"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["library.note.editor"].firstMatch.exists)

        let editButton = app.buttons["library.item.edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 4))
        activate(editButton)

        #if os(macOS)
        XCTAssertTrue(app.descendants(matching: .any)["library.editor.title"].firstMatch.waitForExistence(timeout: 4))
        #else
        XCTAssertTrue(editorField(identifier: "library.editor.sourceText").waitForExistence(timeout: 4))
        #endif
        XCTAssertTrue(app.textFields["library.editor.note"].firstMatch.waitForExistence(timeout: 4))
    }

    func testManualLibraryAddEditAndDeleteBusinessFlow() throws {
        #if os(macOS)
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))

        let starButton = app.buttons["library.item.star"].firstMatch
        XCTAssertTrue(starButton.waitForExistence(timeout: 4))
        activate(starButton)

        let deleteButton = app.buttons["library.item.delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 4))
        activate(deleteButton)
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForNonExistence(timeout: 4))
        #else
        launchApp()

        openTab("收藏")
        let addButton = app.buttons["library.empty.manualAdd"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))
        activate(addButton)

        let sourceEditor = editorField(identifier: "library.editor.sourceText")
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 4))
        enterText("manual phrase", into: sourceEditor)

        let translatedEditor = editorField(identifier: "library.editor.translatedText")
        XCTAssertTrue(translatedEditor.waitForExistence(timeout: 4))
        enterText("手动短语", into: translatedEditor)

        let noteField = app.textFields["library.editor.note"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 4))
        enterText("manual note", into: noteField)

        activate(app.buttons["library.editor.save"].firstMatch)
        XCTAssertTrue(app.staticTexts["manual phrase"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["手动短语"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["manual note"].waitForExistence(timeout: 4))

        let editButton = app.buttons["library.item.edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 4))
        activate(editButton)

        let editNoteField = app.textFields["library.editor.note"].firstMatch
        XCTAssertTrue(editNoteField.waitForExistence(timeout: 4))
        enterText(" updated", into: editNoteField)
        activate(app.buttons["library.editor.save"].firstMatch)
        XCTAssertTrue(app.staticTexts["manual note updated"].waitForExistence(timeout: 8))

        revealTrailingSwipeAction(on: app.staticTexts["manual phrase"].firstMatch)
        let deleteButton = app.buttons["library.swipe.delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 4))
        activate(deleteButton)
        XCTAssertTrue(app.staticTexts["还没有收藏"].waitForExistence(timeout: 4))
        #endif
    }

    func testLanguageControlsEnableSwapOnlyForConcreteSource() throws {
        #if os(macOS)
        launchApp(sourceLanguage: "en", targetLanguage: "zh")
        #else
        launchApp()
        #endif

        XCTAssertTrue(translationInputEditor().waitForExistence(timeout: 12))

        #if os(macOS)
        let swapButton = app.buttons["translation.swapDirection"].firstMatch
        XCTAssertTrue(swapButton.waitForExistence(timeout: 4))
        #else
        let initialSwapButton = app.buttons["translation.swapDirection"].firstMatch
        if initialSwapButton.exists {
            XCTAssertFalse(initialSwapButton.isEnabled)
        }

        chooseMenuValue(pickerIdentifier: "translation.sourceLanguage.picker", value: "英文")
        let swapButton = app.buttons["translation.swapDirection"].firstMatch
        XCTAssertTrue(swapButton.waitForExistence(timeout: 4))
        #endif

        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
        activate(swapButton)
        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
        activate(swapButton)
        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
    }

    func testPrimaryTabsReachExpectedInitialSurfaces() throws {
        launchApp()

        XCTAssertTrue(translationInputEditor().waitForExistence(timeout: 12))

        openTab("收藏")
        XCTAssertTrue(waitForAnyStaticText(["还没有收藏", "No Saved Items Yet", "Aún no hay guardados"], timeout: 8))
        XCTAssertTrue(waitForAnyStaticText(["已保存", "Saved", "Guardado"], timeout: 4))
        XCTAssertFalse(waitForAnyStaticText(["本机保存", "Local Storage Only", "Solo almacenamiento local"], timeout: 1))
        let emptyManualAddButton = app.buttons["library.empty.manualAdd"].firstMatch
        XCTAssertTrue(emptyManualAddButton.waitForExistence(timeout: 4))
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            XCTAssertGreaterThan(
                tabBar.frame.minY - emptyManualAddButton.frame.maxY,
                24,
                "Empty library add button should leave visual spacing above the tab bar"
            )
        }

        openTab("设置")
        XCTAssertTrue(app.secureTextFields["settings.deepSeek.token"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["settings.deepSeek.save"].firstMatch.exists)
        XCTAssertTrue(app.buttons["settings.deepSeek.test"].firstMatch.exists)

        openTab("翻译历史")
        XCTAssertTrue(waitForAnyStaticText(["还没有翻译历史", "No Translation History Yet", "Aún no hay historial de traducción"], timeout: 8))

        openTab("翻译")
        XCTAssertTrue(translationInputEditor().waitForExistence(timeout: 8))
    }

    func testSupportedLanguageLocalizationSmoke() throws {
        try XCTSkipIf(isMacUIRun, "Localized tab smoke is covered by iOS/iPadOS UI tests.")
        for language in supportedLanguageSmokeCases {
            app?.terminate()
            launchApp(language: language.code, locale: language.locale)

            XCTAssertTrue(
                translationInputEditor().waitForExistence(timeout: 12),
                "Missing translate input for \(language.code)"
            )
            chooseMenuValue(
                pickerIdentifier: "translation.sourceLanguage.picker",
                value: language.englishSourceOption
            )

            openTab(language.savedTab)
            XCTAssertTrue(
                app.staticTexts[language.emptySavedTitle].waitForExistence(timeout: 8),
                "Missing empty saved title for \(language.code)"
            )

            openTab(language.settingsTab)
            XCTAssertTrue(
                app.secureTextFields["settings.deepSeek.token"].firstMatch.waitForExistence(timeout: 8),
                "Missing settings token field for \(language.code)"
            )

            openTab(language.historyTab)
            XCTAssertTrue(
                app.staticTexts[language.emptyHistoryTitle].waitForExistence(timeout: 8),
                "Missing empty history title for \(language.code)"
            )
        }
    }

    func testSeededLibraryAndSearchContentRender() throws {
        try XCTSkipIf(isMacUIRun, "Swipe actions are covered by iOS/iPadOS; macOS business flow is covered separately.")
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["种子收藏短语"].waitForExistence(timeout: 4))
        let starIcon = app.images["library.item.star"].firstMatch
        XCTAssertTrue(starIcon.waitForExistence(timeout: 4))
        revealLeadingSwipeAction(on: app.staticTexts["seeded library phrase"].firstMatch)
        let starSwipeAction = app.buttons["library.swipe.star"].firstMatch
        if starSwipeAction.waitForExistence(timeout: 2) {
            activate(starSwipeAction)
        } else {
            activate(app.buttons["Unstar"].firstMatch)
        }
        XCTAssertFalse(starIcon.waitForExistence(timeout: 2))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()

        let searchField = app.textFields["library.search.field"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("seeded")

        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["seeded history phrase"].waitForExistence(timeout: 2))

        dismissKeyboardIfNeeded()
        openTab("翻译历史")
        XCTAssertTrue(app.staticTexts["seeded history phrase"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 2))
    }

    func testSeededLibraryAndHistoryRowsScrollVertically() throws {
        try XCTSkipIf(isMacUIRun, "Touch scrolling is covered by iOS/iPadOS UI tests.")
        launchApp(seed: "scroll-swipe-fixture")

        openTab("收藏")
        let firstLibraryRow = app.staticTexts["scroll library item 01"].firstMatch
        XCTAssertTrue(firstLibraryRow.waitForExistence(timeout: 8))
        firstLibraryRow.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["scroll library item 12"].firstMatch.waitForExistence(timeout: 4))

        openTab("翻译历史")
        let firstHistoryRow = app.staticTexts["scroll history item 01"].firstMatch
        XCTAssertTrue(firstHistoryRow.waitForExistence(timeout: 8))
        firstHistoryRow.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["scroll history item 12"].firstMatch.waitForExistence(timeout: 4))
    }

    func testTranslationBusinessFlowCreatesHistoryAndSavedItem() throws {
        launchTranslationApp(translationMode: "success", translationInput: "hello world")

        translate("hello world")

        let finalText = app.descendants(matching: .any)["translation.result.finalText"].firstMatch
        XCTAssertTrue(finalText.waitForExistence(timeout: 8))
        XCTAssertEqual(finalText.label, "你好，世界。")

        let memoryButton = app.buttons["translation.result.memory"].firstMatch
        XCTAssertTrue(memoryButton.waitForExistence(timeout: 4))
        toggleResultMemory(memoryButton)

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["hello world"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["你好，世界。"].waitForExistence(timeout: 4))

        openTab("翻译历史")
        XCTAssertTrue(app.staticTexts["hello world"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["你好，世界。"].waitForExistence(timeout: 4))
    }

    func testStreamingTranslationShowsPartialBeforeFinalResult() throws {
        launchTranslationApp(translationMode: "slow-success", translationInput: "stream this")

        translate("stream this")

        let partialText = app.descendants(matching: .any)["translation.result.partialText"].firstMatch
        XCTAssertTrue(partialText.waitForExistence(timeout: 4))
        XCTAssertEqual(partialText.label, "流式中间译文")

        let finalText = app.descendants(matching: .any)["translation.result.finalText"].firstMatch
        XCTAssertTrue(finalText.waitForExistence(timeout: 8))
        XCTAssertEqual(finalText.label, "流式完成译文")
    }

    func testTranslationTimeoutShowsActionableErrorAndKeepsInputEditable() throws {
        launchTranslationApp(translationMode: "timeout", translationInput: "timeout please")

        translate("timeout please")

        XCTAssertTrue(waitForAnyStaticText(["翻译失败", "Translation Failed"], timeout: 8))
        XCTAssertTrue(
            waitForAnyStaticText(
                [
                    "DeepSeek 响应超时，请稍后重试或缩短文本。",
                    "DeepSeek timed out. Try again later or shorten the text."
                ],
                timeout: 4
            )
        )
        XCTAssertTrue(translationInputEditor().waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["translation.start"].firstMatch.waitForEnabled(timeout: 4))
    }

    func testDeepSeekTokenSettingsSaveTestAndDeleteBusinessFlow() throws {
        launchApp(deepSeekToken: "sk-ui-test-token", deepSeekTokenMode: "success")

        openTab("设置")
        let tokenField = app.secureTextFields["settings.deepSeek.token"].firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 8))

        let saveButton = app.buttons["settings.deepSeek.save"].firstMatch
        XCTAssertTrue(saveButton.waitForEnabled(timeout: 4))
        activate(saveButton)
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.deepSeek.status",
                containingAny: [
                    "Token 已保存在本机。",
                    "The token has been saved on this device.",
                    "El token se guardó en este dispositivo."
                ],
                timeout: 4
            )
        )

        let testButton = app.buttons["settings.deepSeek.test"].firstMatch
        XCTAssertTrue(testButton.waitForEnabled(timeout: 4))
        activate(testButton)
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.deepSeek.status",
                containingAny: [
                    "连接成功，Token 已保存。",
                    "Connection succeeded. The token has been saved.",
                    "La conexión se realizó correctamente. El token se guardó."
                ],
                timeout: 4
            )
        )

        let deleteButton = app.buttons["settings.deepSeek.delete"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 4))
        activate(deleteButton)
        confirmDestructiveAlert(identifier: "settings.deepSeek.delete.confirm", titles: ["删除", "Delete"])
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.deepSeek.status",
                containingAny: [
                    "粘贴 DeepSeek Token，保存后即可翻译。",
                    "Paste your DeepSeek token and save it to start translating.",
                    "Pega tu token de DeepSeek y guárdalo para empezar a traducir."
                ],
                timeout: 4
            )
        )
        XCTAssertFalse(saveButton.isEnabled)
    }

    func testDeepSeekTokenSettingsConnectionFailureIsActionable() throws {
        launchApp(deepSeekToken: "sk-invalid-token", deepSeekTokenMode: "unauthorized")

        openTab("设置")
        let tokenField = app.secureTextFields["settings.deepSeek.token"].firstMatch
        XCTAssertTrue(tokenField.waitForExistence(timeout: 8))

        let testButton = app.buttons["settings.deepSeek.test"].firstMatch
        XCTAssertTrue(testButton.waitForEnabled(timeout: 4))
        activate(testButton)
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.deepSeek.status",
                containingAny: [
                    "Token 无效或已过期。",
                    "The token is invalid or expired.",
                    "El token no es válido o caducó."
                ],
                timeout: 4
            )
        )
    }

    func testSettingsImportExportBusinessFlow() throws {
        let exportURL = temporaryUITestFileURL(fileName: "memory-export.json")
        try? FileManager.default.removeItem(at: exportURL)

        launchApp(seed: "library-search-fixture", memoryExportURL: exportURL)

        openTab("设置")
        let exportButton = app.buttons["settings.export.button"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 8))
        activate(exportButton)
        XCTAssertTrue(waitForFile(at: exportURL, timeout: 4))
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.importExport.status",
                containingAny: ["已导出", "Exported", "Exportado"],
                timeout: 4
            )
        )

        app.terminate()
        launchApp(memoryImportURL: exportURL)

        openTab("设置")
        let importButton = app.buttons["settings.import.button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 8))
        activate(importButton)
        XCTAssertTrue(
            waitForElementLabel(
                identifier: "settings.importExport.status",
                containingAny: ["已导入", "Imported", "Importado"],
                timeout: 4
            )
        )

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["种子收藏短语"].waitForExistence(timeout: 4))
    }

    private func translate(_ text: String) {
        let inputEditor = translationInputEditor()
        XCTAssertTrue(inputEditor.waitForExistence(timeout: 12))
        #if os(macOS)
        #else
        enterText(text, into: inputEditor)
        dismissKeyboardIfNeeded()
        #endif

        let startButton = app.buttons["translation.start"].firstMatch
        XCTAssertTrue(startButton.waitForEnabled(timeout: 4))
        submitTranslation(startButton)
    }

    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.firstMatch.exists else {
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
    }

    private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func enterText(_ text: String, into element: XCUIElement) {
        #if os(macOS)
        element.click()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        pasteFromMenuBar()
        #else
        element.tap()
        element.typeText(text)
        #endif
    }

    #if os(macOS)
    private func pasteFromMenuBar() {
        let editMenu = app.menuBars.menuBarItems["Edit"].firstMatch
        XCTAssertTrue(editMenu.waitForExistence(timeout: 2))
        editMenu.click()

        let pasteItem = app.menuItems["Paste"].firstMatch
        XCTAssertTrue(pasteItem.waitForExistence(timeout: 2))
        pasteItem.click()
    }
    #endif

    private func submitTranslation(_ startButton: XCUIElement) {
        activate(startButton)
    }

    private func toggleResultMemory(_ memoryButton: XCUIElement) {
        activate(memoryButton)
    }

    private func translationInputEditor() -> XCUIElement {
        let identifier = "translation.input.editor"
        let textView = app.textViews[identifier].firstMatch
        if textView.exists {
            return textView
        }
        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private func editorField(identifier: String) -> XCUIElement {
        let textView = app.textViews[identifier].firstMatch
        if textView.exists {
            return textView
        }

        let textField = app.textFields[identifier].firstMatch
        if textField.exists {
            return textField
        }

        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private var isMacUIRun: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private func revealTrailingSwipeAction(on element: XCUIElement) {
        dragHorizontally(on: element, fromX: 0.92, toX: 0.08)
    }

    private func revealLeadingSwipeAction(on element: XCUIElement) {
        dragHorizontally(on: element, fromX: 0.08, toX: 0.92)
    }

    private func dragHorizontally(on element: XCUIElement, fromX: CGFloat, toX: CGFloat) {
        XCTAssertTrue(element.waitForExistence(timeout: 4))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: 0.5))
        start.press(
            forDuration: 0.15,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.8
        )
    }

    private func openTab(_ title: String) {
        for identifier in tabIdentifiers(for: title) {
            for button in [app.tabBars.buttons[identifier].firstMatch, app.buttons[identifier].firstMatch] {
                if button.waitForExistence(timeout: 1) {
                    activate(button)
                    return
                }
            }
        }

        for label in tabLabels(for: title) {
            let tab = app.tabBars.buttons[label].firstMatch
            if tab.waitForExistence(timeout: 1) {
                activate(tab)
                return
            }

            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                activate(button)
                return
            }
        }

        XCTFail("Missing navigation item: \(title)")
    }

    private func tabIdentifiers(for title: String) -> [String] {
        switch title {
        case "翻译", "Translate":
            return ["tab.translate", "navigation.translate", "text.bubble"]
        case "收藏", "Saved":
            return ["tab.library", "navigation.library", "bookmark"]
        case "翻译历史", "History":
            return ["tab.history", "navigation.history", "clock.arrow.circlepath"]
        case "设置", "Settings":
            return ["tab.settings", "navigation.settings", "gearshape"]
        default:
            return []
        }
    }

    private func tabLabels(for title: String) -> [String] {
        switch title {
        case "翻译", "Translate":
            return ["翻译", "Translate"]
        case "收藏", "Saved":
            return ["收藏", "Saved"]
        case "翻译历史", "History":
            return ["翻译历史", "History"]
        case "设置", "Settings":
            return ["设置", "Settings"]
        default:
            return [title]
        }
    }

    private func chooseMenuValue(pickerIdentifier: String, value: String) {
        let picker = firstExistingElement([
            app.buttons[pickerIdentifier].firstMatch,
            app.popUpButtons[pickerIdentifier].firstMatch,
            app.descendants(matching: .any)[pickerIdentifier].firstMatch
        ], timeout: 4)
        XCTAssertTrue(picker.waitForExistence(timeout: 4), "Missing picker: \(pickerIdentifier)")
        activate(picker)

        let option = firstExistingElement([
            app.buttons[value].firstMatch,
            app.menuItems[value].firstMatch,
            app.staticTexts[value].firstMatch,
            app.descendants(matching: .any)[value].firstMatch
        ], timeout: 4)
        XCTAssertTrue(option.waitForExistence(timeout: 4), "Missing menu option: \(value)")
        activate(option)
    }

    private func firstExistingElement(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement {
        for element in elements where element.waitForExistence(timeout: timeout) {
            return element
        }
        return elements.last ?? app.descendants(matching: .any).firstMatch
    }

    private func confirmDestructiveAlert(identifier: String? = nil, titles: [String]) {
        if let identifier {
            let identifiedButton = app.buttons[identifier].firstMatch
            if identifiedButton.waitForExistence(timeout: 2) {
                activate(identifiedButton)
                return
            }
        }

        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 2) {
            for title in titles {
                let button = alert.buttons[title].firstMatch
                if button.waitForExistence(timeout: 1) {
                    activate(button)
                    return
                }
            }
            XCTFail("Missing destructive alert button: \(titles.joined(separator: ", "))")
            return
        }

        for title in titles {
            let button = app.buttons[title].firstMatch
            if button.waitForExistence(timeout: 1) {
                activate(button)
                return
            }
        }
        XCTFail("Missing destructive button: \(titles.joined(separator: ", "))")
    }

    private func waitForAnyStaticText(_ candidates: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if candidates.contains(where: { app.staticTexts[$0].firstMatch.exists }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return candidates.contains(where: { app.staticTexts[$0].firstMatch.exists })
    }

    private func waitForElementLabel(identifier: String, containingAny expectedTexts: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if matchingElementLabel(identifier: identifier, containingAny: expectedTexts) != nil {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return matchingElementLabel(identifier: identifier, containingAny: expectedTexts) != nil
    }

    private func matchingElementLabel(identifier: String, containingAny expectedTexts: [String]) -> String? {
        let candidates = app.staticTexts.matching(identifier: identifier).allElementsBoundByIndex
            + [app.descendants(matching: .any)[identifier].firstMatch]

        for element in candidates where element.exists {
            let value = element.value as? String
            if expectedTexts.contains(where: { element.label.contains($0) || value?.contains($0) == true }) {
                return element.label
            }
        }
        return nil
    }

    private func temporaryUITestFileURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WordSceneUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var supportedLanguageSmokeCases: [LanguageSmokeCase] {
        [
            LanguageSmokeCase(
                code: "zh-Hans",
                locale: "zh_CN",
                englishSourceOption: "英文",
                savedTab: "收藏",
                settingsTab: "设置",
                historyTab: "翻译历史",
                emptySavedTitle: "还没有收藏",
                emptyHistoryTitle: "还没有翻译历史"
            ),
            LanguageSmokeCase(
                code: "en",
                locale: "en_US",
                englishSourceOption: "English",
                savedTab: "Saved",
                settingsTab: "Settings",
                historyTab: "History",
                emptySavedTitle: "No Saved Items Yet",
                emptyHistoryTitle: "No Translation History Yet"
            ),
            LanguageSmokeCase(
                code: "es",
                locale: "es_ES",
                englishSourceOption: "Inglés",
                savedTab: "Guardados",
                settingsTab: "Ajustes",
                historyTab: "Historial",
                emptySavedTitle: "Aún no hay guardados",
                emptyHistoryTitle: "Aún no hay historial de traducción"
            )
        ]
    }
}

private struct LanguageSmokeCase {
    let code: String
    let locale: String
    let englishSourceOption: String
    let savedTab: String
    let settingsTab: String
    let historyTab: String
    let emptySavedTitle: String
    let emptyHistoryTitle: String
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func waitForDisabled(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
