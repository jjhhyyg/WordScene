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

Status: Milestone 5 in progress; the production Core Data store is now CloudKit-capable, with local migration and recovery paths in place.

Baseline already completed:

- XcodeGen project with iOS and macOS targets.
- Shared SwiftUI app shell with Translate, Library, Search, and Settings sections.
- Responsive startup UI for iPhone, iPad, and macOS, including the latest iPhone/iPad/macOS layout refinements.
- Keychain abstraction.
- DeepSeek balance response decoder and tests.
- DeepSeek token save/delete/test flow in Settings.
- DeepSeek token validation rejects authenticated but balance-unavailable accounts.
- DeepSeek chat-completions translation loop in Translate.
- DeepSeek translation requests use JSON Output, send the source/target/text as a structured JSON prompt payload, parse only `translated_text`, retry one empty assistant response, and reject truncated/filter/resource finish reasons before saving history.
- Debug builds can optionally record raw API responses locally for model-response diagnosis; Release builds do not expose or wire this recorder.
- Translation provider abstraction with an OpenAI-compatible Chat Completions adapter and a DeepSeek provider wrapper.
- Local recent translation history backed by `UserDefaults`.
- Recent translation history deduplicates repeated translations by normalized source text, translated text, and language direction.
- Local memory library backed by `UserDefaults`, with favorite/unfavorite, delete, and note editing.
- Library supports manual local memory entry so users can add source/translation pairs without a network translation request.
- Versioned local persistence documents for memory library and recent history, with legacy array migration.
- Local search across saved memory and recent history, including Chinese pinyin matching.
- Language direction model and tests.
- Pinyin transliterator and tests.
- Core Data is configured with the project CloudKit container for the production persistent store.
- CloudKit sync is entitlement-gated at runtime so unsigned or non-iCloud builds stay local-only instead of crashing.
- Settings separates primary storage status from iCloud sync readiness so local-only mode is visible.
- Settings observes Core Data CloudKit event notifications and surfaces waiting, success, and error states.
- The latest CloudKit sync event is persisted locally so Settings can restore recent sync diagnostics after relaunch.
- Library, Search, and Translate refresh local view state after persistent store remote-change notifications.
- Settings import records local data changes so already loaded Library/Search/Translate views can refresh after an import.
- Memory library and recent-history repository writes record local data changes so already loaded Library/Search/Translate views can refresh after normal save/delete/history updates.
- Settings surfaces network availability so offline sync/translation pauses are explicit while local data remains usable.
- Settings shows the app version, build number, and a smoke-test identifier so manual release evidence can be recorded from inside the app.
- Import/export surfaces that exported JSON is unencrypted, contains saved content, and excludes the API token.
- Release smoke testing is defined in `docs/release-smoke-test.md` for translation, import/export, recovery, iCloud sync, deletion sync, and local-only fallback.
- Release candidate build evidence is recorded in `docs/release-smoke-evidence.md`, including the Git commit used for candidate traceability.
- Non-manual release readiness checks are runnable through `scripts/verify_release_readiness.sh`, including unsigned Release compiles for macOS and iOS.
- App Store privacy manifest coverage exists for app-local `UserDefaults` usage through `WordScene/Resources/PrivacyInfo.xcprivacy`.
- Release readiness scans production source for Apple required-reason API categories so future API additions cannot silently drift from `PrivacyInfo.xcprivacy`.
- Settings no longer exposes anonymous crash-reporting consent until a real crash-reporting service exists, so the visible privacy surface matches implemented behavior.
- Project configuration and v2 design docs now match the implemented privacy surface: first release has no crash-diagnostics upload control.
- Release candidate builds can be run and recorded through `scripts/run_release_candidate_gate.sh`.
- Release candidate gate refuses to generate evidence from a dirty worktree so candidate commit metadata stays reproducible.
- macOS signing recovery steps are documented in `docs/release-signing-runbook.md`.
- Release signing failures can be classified through `scripts/diagnose_release_signing.sh`.
- Manual smoke results can be recorded consistently through `scripts/record_release_smoke_result.sh`.
- Manual smoke recording rejects non-canonical Area/Platform pairs so typos cannot create evidence rows ignored by release completion.
- Manual smoke recording requires current release candidate Git metadata before writing evidence rows.
- Manual smoke recording requires PASS release candidate build evidence for the platform being tested.
- Manual smoke readiness can be listed through `scripts/manual_smoke_readiness.sh` so eligible rows are explicit before recording evidence.
- Real DeepSeek translation protocol can be smoke-tested and recorded without a signed app through `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`.
- Final release completion evidence can be audited through `scripts/check_release_completion.sh`, including candidate Git commit metadata.
- Release completion and manual smoke recording accept candidate evidence from an ancestor commit only when later commits are limited to release evidence/progress documentation.
- Release completion and manual smoke recording reject candidate evidence after product, project, script, checklist, or other release-critical changes.
- Translation execution is now covered by a testable workflow object that verifies token lookup, provider invocation, recent-history persistence, missing-token failure, and non-blocking history-save warnings.

Known gaps:

- CloudKit/iCloud sync is wired at the store configuration and entitlement level, but cross-device sync still needs a signed-device smoke test.
- macOS signed Release builds currently require a valid Xcode Apple Developer account session and a matching Mac App Development provisioning profile before smoke testing can start.
- Import/export still needs a manual macOS and iOS smoke test before release.
- The release smoke checklist exists, but its evidence table has not been filled for a signed release candidate yet.

## Milestone 1: Real Translation Loop

Target status: completed.

Deliverables:

- Settings page loads, saves, deletes, and validates the DeepSeek token through Keychain.
- Token validation requires both authentication success and available DeepSeek balance status.
- Translate page reads the saved token and calls DeepSeek.
- Code-level translation calls go through a provider abstraction instead of hard-coding DeepSeek directly into UI logic.
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
- Manually create a saved library item without requiring a network translation request.
- Add favorite/unfavorite.
- Store source text, translated text, source language, target language, timestamps, and notes.
- Library page lists saved items with empty/loading/content states.

Verification:

- Unit tests for persistence encode/decode and update/delete behavior.
- Unit tests for manual item trimming, duplicate replacement, and blank entry rejection.
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
- Show an explicit privacy notice that exported JSON is not encrypted and must be protected by the user.
- Wire Settings import/export buttons to native file importer/exporter flows.

Verification:

- Round-trip JSON test.
- Settings import/export controller tests.
- Export privacy notice test.
- Manual export/import test on macOS and iOS.

## Milestone 5: Sync Readiness

Target status: in progress.

Deliverables:

- Decide whether to use SwiftData/Core Data with CloudKit or a custom JSON-backed sync layer.
- Add data model migration story before shipping sync.
- Keep local-only mode fully usable.
- Store local memory and recent history in versioned documents while retaining compatibility with legacy array data.
- Configure the production Core Data store with the app's CloudKit container and persistent history tracking.
- Add iCloud entitlements for the shared iOS/macOS targets.
- Keep the Core Data model compatible with CloudKit validation rules and keep persistent history enabled for local fallback stores.
- Surface storage bootstrap status and iCloud sync readiness as separate states in Settings.
- Observe `NSPersistentCloudKitContainer` sync events so recent sync success and errors are visible.
- Persist the latest CloudKit sync event locally so relaunch does not reset diagnostics to an unhelpful waiting state.
- Refresh translation, library, and search screens after persistent store remote-change notifications so synced items can appear without relaunch.
- Refresh already loaded local views after Settings imports memory data.
- Surface offline, constrained, and available network states in Settings without blocking local library/search usage.

Verification:

- Data migration tests.
- Store-description tests for CloudKit container options and remote-change history tracking.
- Runtime sync-mode selection tests for signed CloudKit and unsigned local-only processes.
- Sync event status tests for waiting, success, and failure states.
- Sync event persistence tests across monitor recreation and local-only mode.
- Settings import data-change tests at controller and app-data-controller integration layers.
- Network status tests for offline local-availability messaging.
- Model validation tests for CloudKit-compatible attributes.
- Cross-device manual sync test after CloudKit entitlements and container are confirmed.
- Completed release smoke evidence in `docs/release-smoke-test.md` for the target release candidate.

## Implementation Log

### 2026-05-29

- Committed the initial SwiftUI app bootstrap as `e272641 Bootstrap Word Scene app`.
- Confirmed initial UI is acceptable on iPhone, iPad, and macOS.
- Started Milestone 1.
- Added this implementation plan and progress document.
- Added a local ignored DeepSeek token file under `.local/`.
- Implemented Keychain-backed DeepSeek token save/delete/test controls in Settings.
- Implemented the DeepSeek chat-completions translation client with `deepseek-v4-flash` and non-thinking mode.
- Refactored the translation client behind a `TranslationProvider` abstraction with an OpenAI-compatible Chat Completions adapter and a DeepSeek provider wrapper.
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
- Added a Settings recovery affordance for early local documents: export raw `UserDefaults` payloads as a backup, then reset only the known legacy memory/history keys after confirmation.
- Added recovery controller tests proving raw corrupt documents are exportable and reset does not touch unrelated preferences.
- Switched the production Core Data stack to `NSPersistentCloudKitContainer` with the configured `iCloud.com.erikssonhou.leximemory` container.
- Added CloudKit entitlements for the shared iOS/macOS targets.
- Surfaced the configured iCloud sync mode in Settings persistence status instead of describing the store as local-only.
- Added tests for CloudKit store-description options and persistence status messaging.
- Added runtime entitlement gating so unsigned test builds fall back to local-only storage instead of constructing CloudKit containers.
- Kept persistent history and remote-change notifications enabled for local fallback stores to avoid reopening an existing history-tracked SQLite store in read-only mode.
- Made programmatic Core Data attributes CloudKit-compatible by allowing optional fields at the store layer while retaining domain-model defaults when reading.
- Added tests for entitlement-based sync-mode selection, local fallback history tracking, and CloudKit model compatibility.
- Added provider tests proving the OpenAI-compatible adapter builds the expected Chat Completions request and that the DeepSeek translation client delegates through the provider boundary.

### 2026-05-30

- Split primary storage status from iCloud sync readiness in `AppDataController`.
- Updated Settings to show Core Data availability separately from CloudKit configured, local-only, and sync-unavailable states.
- Added tests for CloudKit-configured, local-only, and unavailable sync status reporting.
- Added a CloudKit sync event monitor backed by `NSPersistentCloudKitContainer.eventChangedNotification`.
- Updated Settings to show waiting, recent success, and error states for CloudKit sync events.
- Added tests for initial sync-event waiting, successful import, and failed export status reporting.
- Persisted the latest CloudKit sync event snapshot in `UserDefaults` and restored it for Settings diagnostics after relaunch.
- Added tests proving persisted sync events restore for CloudKit mode without leaking into local-only mode.
- Added `docs/release-smoke-test.md` as the manual release gate covering translation, language controls, import/export, recovery, iCloud sync, deletion sync, and local-only fallback.
- Added an explicit export privacy notice in Settings and export preparation metadata: exported JSON is unencrypted, contains saved content, and excludes the API token.
- Added a Settings import/export controller test for the export privacy notice.
- Rejected DeepSeek balance responses with `is_available=false` during token testing so authenticated but unusable accounts are not saved as valid.
- Added a DeepSeek balance client test for the authenticated-but-unavailable token path and surfaced a specific Settings error message.
- Added an app data change monitor for persistent store remote-change notifications and wired Translate, Library, and Search to reload local state when synced Core Data changes arrive.
- Cleaned URLProtocol-backed networking tests to avoid Swift 6 data-race diagnostics on clean builds.
- Added network availability monitoring in Settings so offline, constrained, and available states are explicit while local storage remains usable.
- Added tests proving offline network status messaging preserves local library/search/delete availability.
- Added a manual Library entry flow so source/translation pairs can be saved locally without calling DeepSeek.
- Added tests proving manual memory entries trim text, replace duplicates, and reject blank source or translation fields.
- Added a local data-change notification after successful Settings import so loaded Library, Search, and Translate views can refresh without relaunch.
- Added tests proving Settings import records a local data change through both the import controller and `AppDataController`.
- Added an explicit iPad supported-orientation declaration for Release candidate builds.
- Added `scripts/build_release_candidates.sh` to make macOS and iOS Release candidate build attempts reproducible, including platform-specific reruns.
- Verified the iOS signed Release build can be produced locally through the release candidate script, with iPad all-orientation metadata present in the built app; macOS signing remains blocked by missing Xcode account/profile state on this machine.
- Added `scripts/collect_release_candidate_evidence.sh` plus a shell regression test so candidate build metadata can be recorded from the built app bundle.
- Recorded initial release candidate evidence for the iOS signed build and the current macOS signing blocker in `docs/release-smoke-evidence.md`.
- Added `scripts/verify_release_readiness.sh` with a shell regression test so non-manual release gates can be rerun consistently before smoke testing.
- Added `scripts/run_release_candidate_gate.sh` with a shell regression test so candidate build evidence and platform-specific signing blockers are recorded by one command.
- Verified the candidate gate records the macOS signing blocker while still continuing to collect iOS signed-build evidence.
- Hardened the DeepSeek translation adapter to request JSON Output, extract only `translated_text`, retry one empty assistant response, and surface truncated/filter/resource finish reasons as explicit translation errors.
- Structured the DeepSeek user prompt payload as JSON so the model translates only the `text` field instead of receiving a free-form `Text:` block.
- Added `scripts/run_live_deepseek_translation_smoke.sh` plus a shell regression test so the real DeepSeek JSON Output path can be checked with the ignored local token before signed app smoke testing.
- Added a Debug-only Raw API Response recorder for the OpenAI-compatible provider, including a Settings debug switch, local capped `UserDefaults` storage, and tests proving the recorder captures responses only when enabled.
- Updated the release candidate gate so each run replaces stale candidate build evidence while preserving non-manual readiness and live DeepSeek smoke records.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; macOS remains blocked by missing Xcode account/profile state, while iOS signed Release candidate evidence was refreshed.
- Reran `scripts/verify_release_readiness.sh`; script syntax checks, shell regression tests, token leak scan, XcodeGen marker scan, the macOS 72-test suite, and the iOS generic build passed.
- Added `docs/release-signing-runbook.md` so the current macOS signing blocker is treated as an Xcode account/profile recovery task instead of a project configuration change.
- Reran `scripts/run_live_deepseek_translation_smoke.sh`; the ignored local token still works against the real DeepSeek JSON Output path without printing the token.
- Added `scripts/diagnose_release_signing.sh` and wired it into the release candidate gate so macOS signing failures are recorded as actionable account/profile diagnostics instead of raw log excerpts.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence refreshed, and macOS is still blocked by missing Xcode account session plus missing Mac App Development provisioning profile.
- Reran `scripts/verify_release_readiness.sh`; the signing diagnosis tests are now part of the non-manual gate and the macOS 72-test suite plus iOS generic build still pass.
- Added `scripts/record_release_smoke_result.sh` plus a shell regression test so manual release smoke rows are appended with validated result values and escaped Markdown table cells.
- Added unsigned macOS and iOS Release compile checks to `scripts/verify_release_readiness.sh` so Release-only conditional compilation is covered before signed candidate smoke testing.
- Updated the release candidate gate to rerun release readiness and replace stale non-manual gate evidence before recording candidate build evidence or signing blockers.
- Added `scripts/check_release_completion.sh` plus a shell regression test so the release cannot be called complete until signed candidate builds, manual smoke rows, iCloud create/delete sync, and local-only fallback all have PASS evidence with no BLOCKED/FAIL rows remaining.
- Added `WordScene/Resources/PrivacyInfo.xcprivacy` with a `UserDefaults` required-reason declaration and wired a privacy manifest check into release readiness.
- Removed the no-op anonymous crash-reporting toggle from Settings and added a privacy surface check to release readiness so visible privacy controls do not claim unimplemented telemetry behavior.
- Updated `docs/project-config.md` and `docs/v2-design.md` to remove stale crash-reporting consent claims and keep release privacy documentation aligned with the implemented product.
- Added `scripts/test_required_reason_api_scan.sh` and wired it into release readiness so production source usage of `UserDefaults` remains covered by the manifest and other required-reason API categories force an explicit manifest review before release.
- Extended the live DeepSeek smoke script with `--evidence` so successful real API checks replace stale non-manual evidence rows without writing the token, then refreshed the current live protocol evidence.
- Added Git commit metadata to release candidate build evidence and made the final release completion audit fail when candidate traceability metadata is missing.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS signed Release candidate evidence now includes the source Git commit, while macOS remains blocked by missing Xcode account session plus missing Mac App Development provisioning profile.
- Reran `scripts/check_release_completion.sh`; candidate Git commit metadata is now present, and the remaining blockers are macOS signed candidate build plus manual translation/import-export/recovery/iCloud/local-only smoke evidence.
- Hardened `scripts/record_release_smoke_result.sh` so rerunning a manual smoke row for the same area/platform replaces stale evidence instead of leaving contradictory PASS/FAIL/BLOCKED rows in the release evidence file.
- Hardened `scripts/check_release_completion.sh` so each required release row must have exactly one PASS entry, preventing duplicate stale PASS rows from making completion evidence look cleaner than it is.
- Hardened `scripts/check_release_completion.sh` to validate standard evidence table headers for release gate, candidate build, blocker, and manual smoke sections before treating rows as auditable release evidence.
- Deduplicated recent translation history insertion so repeating the same source/translation/language direction moves the newest record to the top instead of cluttering the history list.
- Hardened `scripts/record_release_smoke_result.sh` to reject non-canonical manual Area/Platform pairs, preventing typo rows such as `iPadOS` from being recorded but ignored by the completion audit.
- Hardened `scripts/check_release_completion.sh` so candidate build evidence must match the current repository HEAD or an ancestor with only evidence/progress documentation changed afterward, preventing stale signed-build evidence from making a changed product tree look releasable.
- Hardened `scripts/run_release_candidate_gate.sh` so signed candidate evidence cannot be generated while the git worktree has uncommitted changes.
- Hardened `scripts/record_release_smoke_result.sh` so manual smoke rows cannot be recorded unless release candidate evidence exists for the current repository HEAD or an ancestor with only evidence/progress documentation changed afterward.
- Hardened `scripts/record_release_smoke_result.sh` so platform-specific manual smoke rows require matching PASS candidate build evidence before they can be recorded.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; readiness passed, iOS signed Release candidate evidence was refreshed for commit `b5e5741f9aa7`, and macOS remains blocked by missing Xcode account session plus missing Mac App Development provisioning profile.
- Reran `scripts/check_release_completion.sh`; candidate Git commit metadata now matches the current commit, and the remaining blockers are macOS signed candidate build plus manual translation/import-export/recovery/iCloud/local-only smoke evidence.

### 2026-05-30

- Fixed the release evidence freshness rule so committing evidence/progress documentation after a clean candidate build does not invalidate that candidate by itself.
- Added regression coverage for candidate evidence that points to an ancestor commit with only `docs/release-smoke-evidence.md` and `docs/implementation-plan.md` changed afterward.
- Added regression coverage proving product/source and release script changes after a candidate build still force a fresh candidate gate run before completion or manual smoke evidence can be accepted.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; readiness passed, iOS signed Release candidate evidence was refreshed for commit `9c4ecc9ec1d6`, and macOS remains blocked by missing Xcode account session plus missing Mac App Development provisioning profile.
- Extracted the Translate screen's business action into `TranslationWorkflow` so the token-read -> provider-call -> `TranslationRecord` -> recent-history persistence path is directly testable outside SwiftUI layout code.
- Added `TranslationWorkflowTests` covering successful translation history persistence, missing-token failure before provider invocation, and successful translation with a non-blocking history-save warning.
- Reran `scripts/verify_release_readiness.sh`; non-manual gates still pass after the workflow extraction.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS signed Release candidate evidence was refreshed for commit `423946c46861`, and macOS remains blocked by missing Xcode account session plus missing Mac App Development provisioning profile.
- Tightened the ignored local DeepSeek token file to owner-only permissions and reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; the real API JSON Output path still passes without printing the token.
- Hardened live DeepSeek smoke evidence so it records Git commit metadata, and updated release completion auditing to reject live API smoke evidence that is missing or stale for release-critical changes.
- Reran `scripts/verify_release_readiness.sh`; script self-tests, token leak scan, macOS tests, iOS build, and unsigned Release compiles still pass after the release audit hardening.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all` and `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; iOS candidate and live API smoke evidence now point at commit `370a31ab6316`, while macOS signing remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Hardened manual smoke recording so manual rows cannot be written until current DeepSeek live protocol smoke evidence exists and remains fresh for release-critical files.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, macOS tests, iOS build, and unsigned Release compiles still pass after manual smoke recording hardening.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all` and `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; iOS candidate and live API smoke evidence now point at commit `0da0b9310ae8`, while macOS signing remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Hardened release completion and manual smoke recording so manual PASS rows must use the same build number as the recorded release candidate, preventing stale build smoke results from satisfying the current candidate.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, macOS tests, iOS build, and unsigned Release compiles still pass after build-number consistency hardening.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all` and `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; iOS candidate and live API smoke evidence now point at commit `4151041cfea4`, while macOS signing remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Hardened `scripts/run_live_deepseek_translation_smoke.sh --evidence` so live API evidence refuses a dirty git worktree before writing commit-tagged evidence.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, macOS tests, iOS build, and unsigned Release compiles still pass after live API evidence clean-worktree hardening.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `bf63303c73d0`, while macOS signing remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `d935f20a72c5`.
- Added an `AppDataController` regression proving Settings local recovery reset clears legacy `UserDefaults` documents without removing the current Core Data-backed Library or translation History.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, 78 macOS tests, iOS build, and unsigned Release compiles still pass after the local recovery coverage.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `f82dcb8df41a`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `15d81784f49e`.
- Added a Settings import conflict policy control so users can either overwrite duplicate imported memories or keep existing local entries, with skipped duplicate counts reported accurately.
- Added regression coverage for the keep-existing import path and reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, 79 macOS tests, iOS build, and unsigned Release compiles still pass after the import conflict UI change.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `9d6e8fb3bb2d`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `7e8b27e92b24`.
- Normalized Translate language direction state so changing the source language cannot leave an invalid same-language target selected internally, and translation requests use the normalized direction.
- Added regression coverage for same-language direction normalization and reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, 81 macOS tests, iOS build, and unsigned Release compiles still pass after the language control fix.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `a9cb05318888`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `632fc6004711`.
- Added a Core Data local-only retry path when CloudKit-mode store bootstrap fails, so signed or entitlement/account-problem builds keep the primary local store usable before falling back to legacy JSON storage.
- Added regression coverage proving a CloudKit bootstrap failure retries Core Data local-only and still supports local library writes.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, 82 macOS tests, iOS build, and unsigned Release compiles still pass after the local-only retry path.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `66bfe2acb4e6`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `55cdbed0f128`.
- Split the Settings sync status for entitlement-driven local-only mode from CloudKit-bootstrap-failure local fallback, so users see the actual degradation reason when iCloud store initialization fails.
- Reran `scripts/verify_release_readiness.sh`; release script tests, token leak scan, 82 macOS tests, iOS build, and unsigned Release compiles still pass after the sync-status split.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `c47757fd5232`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `1dbff1ec6233`.
- Added regression coverage proving normal memory-library and recent-history saves record local data changes, then wired those repository writes through `AppDataController` so loaded Library/Search/Translate views can refresh after save/delete/history updates without relaunch.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `dbbc2590d2ca`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `a77fc17af6d9`.
- Relaxed manual evidence recording for `Local-only fallback / macOS/iOS` so the row can be recorded with PASS iOS candidate evidence and the readiness-covered unsigned macOS Release build, matching the checklist's intended unsigned Mac fallback test.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `ef54c78d451b`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `5c23f284eda5`.
- Added `AppBuildInfo` and surfaced version/build/smoke-test identifier in Settings so manual smoke testers can copy the build metadata from the app instead of inspecting the bundle.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `c39eb83105c0`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `e0ac24e00202`.
- Added `scripts/manual_smoke_readiness.sh` plus regression coverage so the currently eligible manual smoke rows can be listed without writing PASS evidence.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `7d76ba8911b5`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.

Next:

- Restore a valid Xcode Apple Developer account session and Mac App Development provisioning profile, then rerun `scripts/build_release_candidates.sh --allow-provisioning-updates --platform macos`.
- After signing is restored, use `scripts/run_release_candidate_gate.sh --allow-provisioning-updates` to regenerate release candidate evidence for both platforms.
- Rerun `scripts/verify_release_readiness.sh` after any release-gate change and before manual smoke testing.
- Execute `docs/release-smoke-test.md` on a signed release candidate and record evidence.
- Run `scripts/check_release_completion.sh` after manual smoke evidence is complete.
- Keep local-only mode fully usable while sync is being prepared.
