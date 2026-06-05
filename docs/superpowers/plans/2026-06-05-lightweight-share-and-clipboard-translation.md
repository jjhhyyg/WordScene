# Lightweight Share and Clipboard Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Apple Translate-inspired Share Extension sheet and an explicit clipboard translation prompt in the main translation tab.

**Architecture:** Keep translation behavior in existing workflows. Add a small, testable clipboard prompt model that contains all decision logic, then wire it into `TranslationView` behind iOS-only pasteboard access. Refactor `ShareTranslationView` presentation only; do not change extraction, translation, handoff, copy, favorite, or open-in-app behavior.

**Tech Stack:** SwiftUI, UIKit pasteboard on iOS, XcodeGen project, XCTest, `Localizable.xcstrings`.

---

## File Structure

- Create `WordScene/Sources/Shared/Features/Translate/TranslationClipboardPrompt.swift`
  - Owns clipboard prompt normalization and decision logic.
  - Contains no UIKit imports so unit tests can exercise it directly.
- Create `WordScene/Tests/TranslationClipboardPromptTests.swift`
  - Covers prompt visibility, dismissal, and accept behavior.
- Modify `WordScene/Sources/Shared/Features/Translate/TranslationView.swift`
  - Adds iOS-only clipboard prompt state and UI.
  - Reads `UIPasteboard.general.string` only on iOS.
  - Applies `.auto` source and `TranslationPreferencesStore.defaultTargetLanguage` before translating.
- Modify `WordScene/Sources/ShareExtension/ShareTranslationView.swift`
  - Refactors the view into a lightweight sheet-like layout.
  - Keeps the existing view model API.
- Modify `WordScene/Resources/Localizable.xcstrings`
  - Adds all new user-facing strings in every supported language.
- Modify `WordScene/Tests/AppLocalizationTests.swift`
  - Adds the new high-risk clipboard/share strings to the explicit English/Spanish guard list if needed.
- Modify `project.yml` and regenerate `WordScene.xcodeproj/project.pbxproj` if the new source file is not automatically included by existing source paths.

## Task 1: Clipboard Prompt Model

**Files:**
- Create: `WordScene/Sources/Shared/Features/Translate/TranslationClipboardPrompt.swift`
- Test: `WordScene/Tests/TranslationClipboardPromptTests.swift`

- [ ] **Step 1: Write failing tests**

Create `WordScene/Tests/TranslationClipboardPromptTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/TranslationClipboardPromptTests CODE_SIGNING_ALLOWED=NO
```

Expected: build fails because `TranslationClipboardPrompt` does not exist.

- [ ] **Step 3: Implement model**

Create `WordScene/Sources/Shared/Features/Translate/TranslationClipboardPrompt.swift`:

```swift
import Foundation

struct TranslationClipboardPrompt: Equatable {
    struct Acceptance: Equatable {
        let inputText: String
        let sourceLanguage: LanguageSelection
        let targetLanguage: LanguageSelection
    }

    let text: String

    static func make(
        clipboardText: String?,
        currentInput: String,
        dismissedText: String?
    ) -> TranslationClipboardPrompt? {
        guard let clipboardText else {
            return nil
        }

        let normalizedClipboard = normalized(clipboardText)
        guard !normalizedClipboard.isEmpty else {
            return nil
        }

        if normalizedClipboard == normalized(currentInput) {
            return nil
        }

        if normalizedClipboard == dismissedText {
            return nil
        }

        return TranslationClipboardPrompt(text: normalizedClipboard)
    }

    func acceptance(defaultTargetLanguage: LanguageSelection) -> Acceptance {
        Acceptance(
            inputText: text,
            sourceLanguage: .auto,
            targetLanguage: LanguageSelection.translationTargets.contains(defaultTargetLanguage) ? defaultTargetLanguage : .zh
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run the same command as Step 2.

Expected: `TranslationClipboardPromptTests` passes.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Sources/Shared/Features/Translate/TranslationClipboardPrompt.swift WordScene/Tests/TranslationClipboardPromptTests.swift
git commit -m "Add clipboard translation prompt model"
```

## Task 2: Clipboard Prompt in TranslationView

**Files:**
- Modify: `WordScene/Sources/Shared/Features/Translate/TranslationView.swift`
- Modify: `WordScene/Resources/Localizable.xcstrings`
- Modify: `WordScene/Tests/AppLocalizationTests.swift`

- [ ] **Step 1: Add failing localization coverage**

Add these keys to `testHighRiskDynamicStringsHaveEnglishAndSpanishTranslations` in `WordScene/Tests/AppLocalizationTests.swift`:

```swift
"检测到剪贴板文本",
"翻译剪贴板",
"忽略剪贴板文本",
```

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the new keys are missing from `Localizable.xcstrings`.

- [ ] **Step 2: Add localized strings**

Add all three keys to `WordScene/Resources/Localizable.xcstrings` for all 18 supported languages.

Required English values:

```text
检测到剪贴板文本 = Clipboard text detected
翻译剪贴板 = Translate Clipboard
忽略剪贴板文本 = Ignore Clipboard Text
```

Required Spanish values:

```text
检测到剪贴板文本 = Texto del portapapeles detectado
翻译剪贴板 = Traducir portapapeles
忽略剪贴板文本 = Ignorar texto del portapapeles
```

- [ ] **Step 3: Wire prompt state into TranslationView**

Add state near existing `@State` properties:

```swift
@State private var clipboardPrompt: TranslationClipboardPrompt?
@State private var dismissedClipboardText: String?
```

Add `.onAppear` or `.task` integration after existing setup:

```swift
#if os(iOS)
refreshClipboardPrompt()
#endif
```

Add the prompt into compact and non-compact translation content above the main translation panel:

```swift
clipboardPromptBanner
```

Implement iOS-only helpers in `TranslationView`:

```swift
#if os(iOS)
@ViewBuilder
private var clipboardPromptBanner: some View {
    if let clipboardPrompt {
        HStack(spacing: 12) {
            Label(String(localized: "检测到剪贴板文本"), systemImage: "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 8)

            Button(String(localized: "翻译剪贴板")) {
                Task {
                    await acceptClipboardPrompt(clipboardPrompt)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                dismissClipboardPrompt(clipboardPrompt)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "忽略剪贴板文本"))
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("translation.clipboardPrompt")
    }
}

private func refreshClipboardPrompt() {
    clipboardPrompt = TranslationClipboardPrompt.make(
        clipboardText: UIPasteboard.general.string,
        currentInput: inputText,
        dismissedText: dismissedClipboardText
    )
}

@MainActor
private func acceptClipboardPrompt(_ prompt: TranslationClipboardPrompt) async {
    let action = prompt.acceptance(defaultTargetLanguage: TranslationPreferencesStore().defaultTargetLanguage)
    translationGeneration += 1
    inputText = action.inputText
    sourceLanguage = action.sourceLanguage
    targetLanguage = action.targetLanguage
    clipboardPrompt = nil
    await translateInput()
}

private func dismissClipboardPrompt(_ prompt: TranslationClipboardPrompt) {
    dismissedClipboardText = prompt.text
    clipboardPrompt = nil
}
#else
private var clipboardPromptBanner: some View {
    EmptyView()
}
#endif
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests -only-testing:WordSceneTests/TranslationClipboardPromptTests CODE_SIGNING_ALLOWED=NO
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit**

```bash
git add WordScene/Sources/Shared/Features/Translate/TranslationView.swift WordScene/Resources/Localizable.xcstrings WordScene/Tests/AppLocalizationTests.swift
git commit -m "Add clipboard translation prompt"
```

## Task 3: Share Extension Lightweight Sheet UI

**Files:**
- Modify: `WordScene/Sources/ShareExtension/ShareTranslationView.swift`

- [ ] **Step 1: Add accessibility anchors before refactor**

Add stable identifiers to the current view before changing layout:

```swift
.accessibilityIdentifier("shareTranslation.content")
.accessibilityIdentifier("shareTranslation.copy")
.accessibilityIdentifier("shareTranslation.favorite")
.accessibilityIdentifier("shareTranslation.open")
```

Run:

```bash
xcodebuild build -project WordScene.xcodeproj -target WordSceneShareExtension -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 2: Refactor ShareTranslationView layout**

Replace the page-like `NavigationStack` presentation with:

- `ZStack` or root `VStack` on `Color(.systemGroupedBackground)`;
- top grabber;
- centered title;
- close-free content because Share Extension dismissal is controlled by host;
- rounded translation card;
- grouped action rows.

Preserve these behaviors exactly:

```swift
onCopy(record.translatedText)
viewModel.markFavorite()
onOpen(viewModel.openURL())
```

The action rows should use these localized labels:

```swift
String(localized: "复制译文")
String(localized: "收藏")
String(localized: "已收藏")
String(localized: "打开")
```

- [ ] **Step 3: Build Share Extension**

Run:

```bash
xcodebuild build -project WordScene.xcodeproj -target WordSceneShareExtension -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add WordScene/Sources/ShareExtension/ShareTranslationView.swift
git commit -m "Refine share extension translation sheet"
```

## Task 4: Final Verification

**Files:**
- Verify working tree only; no production edits expected.

- [ ] **Step 1: Run localization and clipboard tests**

```bash
xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests -only-testing:WordSceneTests/TranslationClipboardPromptTests CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 2: Build main iOS app**

```bash
xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Build Share Extension target**

```bash
xcodebuild build -project WordScene.xcodeproj -target WordSceneShareExtension -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Inspect generated extension bundle localization resources**

```bash
find /Users/erikssonhou/Library/Developer/Xcode/DerivedData/WordScene-*/Build/Products/Debug-iphonesimulator/Translate\\ to\\ WordScene.appex -maxdepth 2 -name 'Localizable.strings' | wc -l
find /Users/erikssonhou/Library/Developer/Xcode/DerivedData/WordScene-*/Build/Products/Debug-iphonesimulator/Translate\\ to\\ WordScene.appex -maxdepth 2 -name 'InfoPlist.strings'
```

Expected:

- first command prints `18` or more;
- second command prints no paths.

- [ ] **Step 5: Commit final verification note only if files changed**

If no files changed, do not commit. If verification required a project-file correction, commit the correction with:

```bash
git add <changed-files>
git commit -m "Verify lightweight translation entry points"
```
