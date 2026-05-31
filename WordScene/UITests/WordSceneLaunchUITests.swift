import XCTest

final class WordSceneLaunchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        launchApp()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func launchApp(seed: String? = nil, language: String? = "zh-Hans", locale: String? = "zh_CN") {
        app = XCUIApplication()
        app.launchArguments.append("-WordSceneUITest")
        if let language {
            app.launchArguments += ["-AppleLanguages", "(\(language))"]
        }
        if let locale {
            app.launchArguments += ["-AppleLocale", locale]
        }
        app.launchEnvironment["WORDSCENE_UI_TEST_SUITE"] = "WordSceneUITests.\(UUID().uuidString)"
        if let seed {
            app.launchEnvironment["WORDSCENE_UI_TEST_SEED"] = seed
        }
        app.launch()
    }

    func testTranslateScreenInitialStateAndInputReadiness() throws {
        let inputEditor = app.textViews["translation.input.editor"].firstMatch
        XCTAssertTrue(inputEditor.waitForExistence(timeout: 12))

        let startButton = app.buttons["translation.start"].firstMatch
        XCTAssertTrue(startButton.exists)
        XCTAssertFalse(startButton.isEnabled)

        let swapButton = app.buttons["translation.swapDirection"].firstMatch
        if swapButton.exists {
            XCTAssertFalse(swapButton.isEnabled)
        }

        inputEditor.tap()
        inputEditor.typeText("hello")

        XCTAssertTrue(startButton.waitForEnabled(timeout: 4))
        XCTAssertFalse(app.buttons["translation.clear"].firstMatch.exists)

        let inputClearButton = app.buttons["translation.input.clear"].firstMatch
        XCTAssertTrue(inputClearButton.waitForExistence(timeout: 4))
        inputClearButton.tap()
        XCTAssertTrue(startButton.waitForDisabled(timeout: 4))
    }

    func testTappingOutsideTranslationInputDismissesKeyboard() throws {
        let inputEditor = app.textViews["translation.input.editor"].firstMatch
        XCTAssertTrue(inputEditor.waitForExistence(timeout: 12))

        inputEditor.tap()
        inputEditor.typeText("hello")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()

        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1))

        let startButton = app.buttons["translation.start"].firstMatch
        XCTAssertTrue(startButton.waitForEnabled(timeout: 4))
        XCTAssertTrue(startButton.waitForHittable(timeout: 4))
    }

    func testExistingLibraryNoteRequiresEditBeforeSavingChanges() throws {
        app.terminate()
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded note"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["library.note.editor"].firstMatch.exists)

        let editButton = app.buttons["library.item.edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 4))
        editButton.tap()

        XCTAssertTrue(app.navigationBars["编辑收藏"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.textFields["可选"].firstMatch.waitForExistence(timeout: 4))
    }

    func testLanguageControlsEnableSwapOnlyForConcreteSource() throws {
        XCTAssertTrue(app.textViews["translation.input.editor"].firstMatch.waitForExistence(timeout: 12))

        let swapButton = app.buttons["translation.swapDirection"].firstMatch
        XCTAssertTrue(swapButton.waitForExistence(timeout: 4))
        XCTAssertFalse(swapButton.isEnabled)

        chooseMenuValue(pickerIdentifier: "translation.sourceLanguage.picker", value: "英文")

        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
        swapButton.tap()
        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
        swapButton.tap()
        XCTAssertTrue(swapButton.waitForEnabled(timeout: 4))
    }

    func testPrimaryTabsReachExpectedInitialSurfaces() throws {
        XCTAssertTrue(app.textViews["translation.input.editor"].firstMatch.waitForExistence(timeout: 12))

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["还没有收藏"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["已保存"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["本机保存"].exists)
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
        XCTAssertTrue(app.staticTexts["还没有翻译历史"].waitForExistence(timeout: 8))

        openTab("翻译")
        XCTAssertTrue(app.textViews["translation.input.editor"].firstMatch.waitForExistence(timeout: 8))
    }

    func testSupportedLanguageLocalizationSmoke() throws {
        for language in supportedLanguageSmokeCases {
            app.terminate()
            launchApp(language: language.code, locale: language.locale)

            XCTAssertTrue(
                app.textViews["translation.input.editor"].firstMatch.waitForExistence(timeout: 12),
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
        app.terminate()
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["种子收藏短语"].waitForExistence(timeout: 4))
        let starIcon = app.images["library.item.star"].firstMatch
        XCTAssertTrue(starIcon.waitForExistence(timeout: 4))
        confirmSwipeLeft(on: app.staticTexts["seeded library phrase"].firstMatch)
        let starSwipeAction = app.buttons["library.swipe.star"].firstMatch
        if starSwipeAction.waitForExistence(timeout: 2) {
            starSwipeAction.tap()
        } else {
            app.buttons["Unstar"].firstMatch.tap()
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
        app.terminate()
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

    private func dismissKeyboardIfNeeded() {
        guard app.keyboards.firstMatch.exists else {
            return
        }

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
    }

    private func confirmSwipeLeft(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(
            forDuration: 0.08,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )
    }

    private func openTab(_ title: String) {
        for identifier in tabIdentifiers(for: title) {
            for button in [app.tabBars.buttons[identifier].firstMatch, app.buttons[identifier].firstMatch] {
                if button.waitForExistence(timeout: 1) {
                    button.tap()
                    return
                }
            }
        }

        for label in tabLabels(for: title) {
            let tab = app.tabBars.buttons[label].firstMatch
            if tab.waitForExistence(timeout: 1) {
                tab.tap()
                return
            }

            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                button.tap()
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
        let picker = app.buttons[pickerIdentifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 4), "Missing picker: \(pickerIdentifier)")
        picker.tap()

        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 4), "Missing menu option: \(value)")
        option.tap()
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
