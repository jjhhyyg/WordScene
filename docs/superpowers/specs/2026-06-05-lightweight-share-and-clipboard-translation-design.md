# Lightweight Share and Clipboard Translation Design

## Goal

Make translation capture feel closer to Apple's Translate sheet while staying inside App Store-safe iOS extension boundaries.

This design covers two entry points:

- Share Extension: selected text is sent through the system Share Sheet, translated immediately, and shown in a lightweight bottom-sheet style interface.
- Clipboard prompt: when the user opens WordScene and the system clipboard contains text, the translation page offers a clear one-tap prompt to translate that clipboard text.

This does not attempt to add a global "Translate by WordScene" command to the system copy/paste edit menu. iOS does not expose a third-party global edit-menu extension point for all apps.

## Scope

In scope:

- Redesign the Share Extension UI to resemble a compact translation sheet.
- Keep the existing Share Extension translation workflow, handoff, copy, favorite, and open-in-app behavior.
- Add a clipboard detection prompt on the main translation page.
- Let the clipboard prompt populate the input with clipboard text and start translation only after the user taps the prompt.
- Keep all new user-facing strings in `Localizable.xcstrings` for every currently supported app language.

Out of scope:

- System-wide copy/paste menu injection.
- Background clipboard monitoring.
- Automatic silent translation on every app launch.
- A separate Safari Web Extension.
- Live Activity or Dynamic Island changes.

## User Experience

### Share Extension

The extension opens as a lightweight translation sheet:

- A grabber and centered title at the top.
- A rounded translation card with:
  - source language summary, using automatic detection when applicable;
  - a compact source text preview;
  - target language label;
  - translated text as the primary visual focus.
- A grouped action list below the result:
  - Copy Translation;
  - Add to Favorites;
  - Open in WordScene.
- Loading and error states use the same sheet structure so the UI does not jump between page-like and sheet-like layouts.

The extension remains localized through its own embedded `Localizable.xcstrings` resource.

### Clipboard Prompt

When the user opens WordScene on iOS and the translation tab is visible:

- If the clipboard contains non-empty text and that text is not already in the input editor, show a compact prompt near the top of the translation page.
- The prompt text says that clipboard text is available and can be translated.
- The primary action imports the clipboard text and starts translation.
- A dismiss action hides the prompt for the current clipboard value.

The app does not translate automatically on launch. This avoids surprising the user, avoids translating stale clipboard content, and makes the iOS clipboard privacy prompt easier to understand.

## Data Flow

### Share Extension Flow

1. `ShareViewController` receives shared item providers.
2. `ShareTranslationViewModel` extracts text through `SharedContentExtractor`.
3. The model translates with:
   - source language: `.auto`;
   - target language: `TranslationPreferencesStore.defaultTargetLanguage`.
4. The translated `ShareExtensionHandoffRecord` is saved to the app group handoff store.
5. The sheet shows the translated record and offers copy, favorite, and open actions.
6. Opening the main app sends the existing `wordscene://share-translation?id=...` URL.
7. `TranslationView` consumes the handoff and displays the same original and translated text.

### Clipboard Prompt Flow

1. `TranslationView` checks the general pasteboard on iOS when the translation page appears.
2. If a candidate text exists, it stores a lightweight prompt model in local view state.
3. When the user taps the prompt action:
   - `inputText` is set to the clipboard text;
   - source language is set to `.auto`;
   - target language is set to `TranslationPreferencesStore.defaultTargetLanguage`;
   - the existing `translateInput()` workflow runs.
4. If the user dismisses the prompt, that exact clipboard text is not prompted again during the current view lifetime.

## Components

### Share Extension UI

`ShareTranslationView` will be refactored into sheet-style sections:

- header;
- translation card;
- action groups;
- loading and error content.

The view model should remain mostly unchanged. UI changes should not alter extraction, translation, handoff, or persistence behavior.

### Clipboard Prompt

Add a small iOS-only clipboard prompt model around `TranslationView`, with testable decision logic separated from UIKit access:

- normalize candidate text by trimming whitespace and newlines;
- do not prompt for empty text;
- do not prompt when the candidate matches the current input;
- do not prompt when the candidate matches a dismissed clipboard value;
- import and translate only after explicit user action.

UIKit pasteboard access stays behind an iOS-only helper so tests can validate the decision logic without reading the real system clipboard.

## Error Handling

Share Extension errors:

- missing shared text: show the existing localized "cannot read shared content" message in the sheet.
- missing token: show the existing localized token setup message.
- translation failure: show the existing localized retry-safe failure message.

Clipboard prompt errors:

- no readable text: no prompt.
- translation failure after user taps: reuse the existing `TranslationView` error state.
- missing token after user taps: reuse the existing token setup error state.

## Localization

All new strings must be added to `WordScene/Resources/Localizable.xcstrings` for the supported languages already enforced by `AppLocalizationTests`:

`zh-Hans`, `zh-Hant`, `en`, `es`, `fr`, `de`, `pt`, `it`, `ru`, `ja`, `ko`, `nl`, `pl`, `ar`, `tr`, `vi`, `id`, `hi`.

The Share Extension must continue embedding `Localizable.xcstrings` in its target resources.

## Testing

Add focused tests before implementation:

- clipboard prompt decision logic:
  - empty clipboard text does not prompt;
  - valid clipboard text prompts;
  - matching current input does not prompt;
  - dismissed clipboard text does not prompt;
  - accepting clipboard text applies `.auto` source and configured default target language.
- route and share handoff tests remain unchanged.
- localization tests must pass for every new string.

Verification commands after implementation:

- `xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -only-testing:WordSceneTests/AppLocalizationTests -only-testing:WordSceneTests/TranslationClipboardPromptTests CODE_SIGNING_ALLOWED=NO`
- `xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild build -project WordScene.xcodeproj -target WordSceneShareExtension -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' CODE_SIGNING_ALLOWED=NO`

## Acceptance Criteria

- Share Extension visually behaves like a lightweight translation sheet rather than a full app page.
- Share Extension copy, favorite, and open-in-app actions still work.
- Opening WordScene with text in the clipboard shows a localized prompt instead of silently translating.
- Tapping the clipboard prompt imports text and starts translation using automatic source detection and the configured default target language.
- New strings are localized for all currently supported languages.
- The app and Share Extension build successfully.
