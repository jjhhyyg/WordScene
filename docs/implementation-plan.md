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

Status: Milestone 5 started; local persistence now has a migration path before CloudKit.

Baseline already completed:

- XcodeGen project with iOS and macOS targets.
- Shared SwiftUI app shell with Translate, Library, Search, and Settings sections.
- Responsive startup UI for iPhone, iPad, and macOS, including the latest iPhone/iPad/macOS layout refinements.
- Keychain abstraction.
- DeepSeek balance response decoder and tests.
- DeepSeek token save/delete/test flow in Settings.
- DeepSeek chat-completions translation loop in Translate.
- Local recent translation history backed by `UserDefaults`.
- Local memory library backed by `UserDefaults`, with favorite/unfavorite, delete, and note editing.
- Versioned local persistence documents for memory library and recent history, with legacy array migration.
- Local search across saved memory and recent history, including Chinese pinyin matching.
- Language direction model and tests.
- Pinyin transliterator and tests.

Known gaps:

- CloudKit/iCloud sync is not connected.
- Import/export still needs a manual macOS and iOS smoke test before release.

## Milestone 1: Real Translation Loop

Target status: completed.

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

Target status: completed.

Deliverables:

- Promote a translation history item into a saved library item.
- Add favorite/unfavorite.
- Store source text, translated text, source language, target language, timestamps, and notes.
- Library page lists saved items with empty/loading/content states.

Verification:

- Unit tests for persistence encode/decode and update/delete behavior.
- Manual smoke test across app relaunch.

## Milestone 3: Search

Target status: completed.

Deliverables:

- Search saved items and recent history.
- Match original text, translated text, language labels, and pinyin terms for Chinese.
- Show no-results and query-empty states.

Verification:

- Unit tests for pinyin-backed search terms.
- Manual smoke test with Chinese and English examples.

## Milestone 4: Import and Export

Target status: implemented in code; manual smoke pending.

Deliverables:

- Export all local memory data as `memory-book-export-YYYYMMDD.json`.
- Import the same JSON format with validation and conflict handling.
- Keep API token out of export files.
- Wire Settings import/export buttons to native file importer/exporter flows.

Verification:

- Round-trip JSON test.
- Settings import/export controller tests.
- Manual export/import test on macOS and iOS.

## Milestone 5: Sync Readiness

Target status: in progress.

Deliverables:

- Decide whether to use SwiftData/Core Data with CloudKit or a custom JSON-backed sync layer.
- Add data model migration story before shipping sync.
- Keep local-only mode fully usable.
- Store local memory and recent history in versioned documents while retaining compatibility with legacy array data.

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
- Confirmed the initial iPhone, iPad, and macOS UI is now acceptable as the baseline for the next product milestone.
- Implemented `MemoryItem` and `MemoryLibraryStore` for saved local memory items.
- Added favorite/unfavorite controls in the translation result and recent history views.
- Replaced the Library placeholder with persisted saved items, empty/loading/content states, deletion, and note editing.
- Added memory library persistence, duplicate prevention, removal, and note update tests.
- Implemented `MemorySearchIndex` for saved memory and recent history search.
- Replaced the Search placeholder with real query-empty, no-results, loading, and content states.
- Added search tests for original text, translated text, language labels, notes, duplicate suppression, and Chinese pinyin.
- Implemented JSON memory import/export with schema version, checksum validation, duplicate conflict handling, and export file naming.
- Wired Settings import/export buttons to native JSON file import/export flows with status feedback and Token exclusion messaging.
- Added import/export service and Settings import/export controller tests.
- Started sync readiness by migrating `UserDefaults` persistence for memory library and recent history from raw arrays to versioned documents.
- Added compatibility tests proving legacy raw-array data loads and is rewritten to `schema_version: 1` documents.
- Started the Core Data local authority layer with programmatic `TranslationItem` and `DeletionTombstone` entities.
- Added in-memory Core Data tests for memory item upsert/load and soft-delete tombstone behavior.
- Added `MemoryLibraryRepository` as the Core Data-backed memory library facade.
- Wired Translate, Library, Search, and Settings import/export memory access to the Core Data repository.
- Added legacy `UserDefaults` migration into Core Data, with migration source cleanup to prevent deleted items from resurfacing.
- Added a Core Data-backed `TranslationHistoryRepository` and `TranslationHistoryRecord` entity for recent translation history.
- Wired Translate and Search recent history access to the Core Data-backed repository.
- Added legacy recent-history migration from `UserDefaults` into Core Data, with old data cleared only after a successful Core Data write.
- Added `AppDataController` as the shared app data entry point so Translate, Library, Search, and Settings use one owned Core Data stack.
- Injected the shared data controller through SwiftUI environment for the main window and macOS Settings scene.
- Added tests proving memory and recent-history repositories share the injected Core Data store.
- Added explicit app persistence status for Core Data bootstrap success/failure.
- Surfaced the persistence status in Settings so legacy fallback mode is visible instead of silent.
- Added tests proving Core Data bootstrap failures are reported through `AppDataController`.
- Added throwing memory-library repository APIs so Core Data read/write failures can be surfaced instead of silently falling back.
- Wired Library, Translate, Search, and Settings import/export memory access to the explicit error path.
- Added throwing translation-history repository APIs so Core Data recent-history read/write failures can be surfaced instead of silently falling back.
- Wired Translate and Search recent-history access to the explicit error path, with non-blocking warnings when translation succeeds but history persistence fails.
- Added explicit `UserDefaults` document decode errors for local memory and recent-history stores.
- Added tests proving corrupt local documents throw through `loadOrThrow()` and are preserved for recovery instead of being cleared or treated as empty.

Next:

- Manually smoke test import/export on macOS and iOS.
- Add an in-app recovery affordance for corrupt local documents, such as export raw backup then reset local cache.
- Enable `NSPersistentCloudKitContainer` only after local Core Data migration and delete behavior are proven.
- Keep local-only mode fully usable while sync is being prepared.
