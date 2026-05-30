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

    private func launchApp(seed: String? = nil) {
        app = XCUIApplication()
        app.launchArguments.append("-WordSceneUITest")
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

        let editButton = app.buttons["编辑收藏"].firstMatch
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

    func testSeededLibraryAndSearchContentRender() throws {
        app.terminate()
        launchApp(seed: "library-search-fixture")

        openTab("收藏")
        XCTAssertTrue(app.staticTexts["seeded library phrase"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["种子收藏短语"].waitForExistence(timeout: 4))
        let starIcon = app.images["library.item.star"].firstMatch
        XCTAssertTrue(starIcon.waitForExistence(timeout: 4))
        confirmSwipeLeft(on: app.staticTexts["seeded library phrase"].firstMatch)
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
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.waitForExistence(timeout: 4) {
            tab.tap()
            return
        }

        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 4), "Missing navigation item: \(title)")
        button.tap()
    }

    private func chooseMenuValue(pickerIdentifier: String, value: String) {
        let picker = app.buttons[pickerIdentifier].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 4), "Missing picker: \(pickerIdentifier)")
        picker.tap()

        let option = app.buttons[value].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 4), "Missing menu option: \(value)")
        option.tap()
    }
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
