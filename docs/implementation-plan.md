# WordScene Implementation Plan

## Product Goal

WordScene should become a usable cross-platform translation memory app for iPhone, iPad, and macOS. The first complete product loop is:

1. Save a DeepSeek API token locally and securely.
2. Translate user input with source/target language controls.
3. Show loading, success, empty, and error states clearly.
4. Persist recent translation history locally.
5. Keep the same core behavior across iPhone, iPad, and macOS.

Cloud sync, import/export, richer library management, and advanced search are later milestones. They should not block the first usable translation loop.

## Current Stage

Status: in progress.

Baseline already completed:

- XcodeGen project with iOS and macOS targets.
- Shared SwiftUI app shell with Translate, Library, Search, and Settings sections.
- Responsive startup UI for iPhone, iPad, and macOS.
- Keychain abstraction.
- DeepSeek balance response decoder and tests.
- Language direction model and tests.
- Pinyin transliterator and tests.

Known gaps:

- Settings UI does not yet persist the DeepSeek token.
- Translate UI does not yet call the real DeepSeek chat/completions API.
- Translation result, loading, and error states are placeholders.
- Translation history is not persisted.
- Library, Search, and import/export remain placeholders.
- CloudKit/iCloud sync is not connected.

## Milestone 1: Real Translation Loop

Target status: next.

Deliverables:

- Settings page loads, saves, deletes, and validates the DeepSeek token through Keychain.
- Translate page reads the saved token and calls DeepSeek.
- Translation request supports auto source language and concrete target language.
- Swap remains disabled when source is auto-detect.
- Result panel shows translating, translated text, missing-token, and failure states.
- Recent history stores successful translations locally and renders in the history panel.

Verification:

- `xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project WordScene.xcodeproj -scheme WordSceneMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- Manual smoke test on macOS: save token, translate a short sentence, verify history updates.
- Manual smoke test on iPhone/iPad Simulator when the matching runtime is available.

## Milestone 2: Local Memory Library

Target status: pending.

Deliverables:

- Promote a translation history item into a saved library item.
- Add favorite/unfavorite.
- Store source text, translated text, source language, target language, timestamps, and notes.
- Library page lists saved items with empty/loading/content states.

Verification:

- Unit tests for persistence encode/decode and update/delete behavior.
- Manual smoke test across app relaunch.

## Milestone 3: Search

Target status: pending.

Deliverables:

- Search saved items and recent history.
- Match original text, translated text, language labels, and pinyin terms for Chinese.
- Show no-results and query-empty states.

Verification:

- Unit tests for pinyin-backed search terms.
- Manual smoke test with Chinese and English examples.

## Milestone 4: Import and Export

Target status: pending.

Deliverables:

- Export all local memory data as `memory-book-export-YYYYMMDD.json`.
- Import the same JSON format with validation and conflict handling.
- Keep API token out of export files.

Verification:

- Round-trip JSON test.
- Manual export/import test on macOS and iOS.

## Milestone 5: Sync Readiness

Target status: pending.

Deliverables:

- Decide whether to use SwiftData/Core Data with CloudKit or a custom JSON-backed sync layer.
- Add data model migration story before shipping sync.
- Keep local-only mode fully usable.

Verification:

- Data migration tests.
- Cross-device manual sync test after CloudKit entitlements and container are confirmed.

## Implementation Log

### 2026-05-29

- Committed the initial SwiftUI app bootstrap as `e272641 Bootstrap Word Scene app`.
- Confirmed initial UI is acceptable on iPhone, iPad, and macOS.
- Started Milestone 1.
- Added this implementation plan and progress document.
- Added a local ignored DeepSeek token file under `.local/`.
- Implemented Keychain-backed DeepSeek token save/delete/test controls in Settings.
- Implemented the DeepSeek chat-completions translation client with `deepseek-v4-flash` and non-thinking mode.
- Implemented translation loading/success/error states in Translate.
- Implemented local recent translation history backed by `UserDefaults`.
- Added tests for DeepSeek translation response decoding and translation history persistence.
- Verified the local token against the DeepSeek API with a direct non-stream request.

Next:

- Manually smoke test the full macOS UI loop: Settings token status, translation button, result rendering, and history rendering.
- Smoke test the same loop on iPhone/iPad Simulator when the desired simulator runtime is available.
- Start Milestone 2 by promoting history entries into saved library items.
