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
- iOS declares the `remote-notification` background mode required by CloudKit push notifications.
- Settings separates primary storage status from iCloud sync readiness so local-only mode is visible.
- Settings observes Core Data CloudKit event notifications and surfaces waiting, success, and error states.
- The latest CloudKit sync event is persisted locally so Settings can restore recent sync diagnostics after relaunch.
- Library, Search, and Translate refresh local view state after persistent store remote-change notifications.
- Settings import records local data changes so already loaded Library/Search/Translate views can refresh after an import.
- Settings import skips persistence and change notifications when every incoming duplicate is skipped, avoiding fake local changes during keep-existing imports.
- Settings import reports keep-existing no-op imports as skipped duplicates instead of implying a successful data import.
- Memory library and recent-history repository writes record local data changes so already loaded Library/Search/Translate views can refresh after normal save/delete/history updates.
- Settings surfaces network availability so offline sync/translation pauses are explicit while local data remains usable.
- Settings shows the app version, build number, and a smoke-test identifier so manual release evidence can be recorded from inside the app.
- Import/export surfaces that exported JSON is unencrypted, contains saved content, and excludes the API token.
- Release smoke testing is defined in `docs/release-smoke-test.md` for translation, import/export, recovery, iCloud sync, deletion sync, and local-only fallback.
- Release candidate build evidence is recorded in `docs/release-smoke-evidence.md`, including the Git commit used for candidate traceability.
- Non-manual release readiness checks are runnable through `scripts/verify_release_readiness.sh`, including macOS unit tests, iOS simulator unit tests, and unsigned Release compiles for macOS and iOS.
- App Store privacy manifest coverage exists for app-local `UserDefaults` usage through `WordScene/Resources/PrivacyInfo.xcprivacy`.
- Release readiness scans production source for Apple required-reason API categories so future API additions cannot silently drift from `PrivacyInfo.xcprivacy`.
- Settings no longer exposes anonymous crash-reporting consent until a real crash-reporting service exists, so the visible privacy surface matches implemented behavior.
- Project configuration and v2 design docs now match the implemented privacy surface: first release has no crash-diagnostics upload control.
- Release candidate builds can be run and recorded through `scripts/run_release_candidate_gate.sh`.
- Release candidate gate refuses to generate evidence from a dirty worktree so candidate commit metadata stays reproducible.
- macOS signing recovery steps are documented in `docs/release-signing-runbook.md`.
- Release signing failures can be classified through `scripts/diagnose_release_signing.sh`.
- Release signing diagnosis defaults to the latest release-candidate log under `/tmp/WordSceneReleaseCandidates/logs`, so the current blocker can be classified without copying the log path.
- Manual smoke results can be recorded consistently through `scripts/record_release_smoke_result.sh`.
- Manual smoke recording rejects non-canonical Area/Platform pairs so typos cannot create evidence rows ignored by release completion.
- Manual smoke recording requires current release candidate Git metadata before writing evidence rows.
- Manual smoke recording requires PASS release candidate build evidence for the platform being tested.
- Manual smoke recording requires `--confirm-executed` before writing PASS or FAIL rows, so command templates cannot be mistaken for evidence from a checklist that was not actually run.
- Manual smoke readiness can be listed through `scripts/manual_smoke_readiness.sh`, with optional command templates, so eligible rows are explicit before recording evidence.
- Manual smoke readiness can append a summary of READY/WAITING counts and grouped WAITING reasons for release triage.
- Release next actions can be listed through `scripts/release_next_actions.sh` so signing recovery, READY manual smoke rows, and completion gating are visible without manually interpreting multiple scripts.
- Manual smoke environment readiness can be checked through `scripts/manual_smoke_environment_preflight.sh`, separating evidence-eligible rows from physical-device availability and executable smoke environments before PASS rows are recorded.
- iOS release candidates can be installed to an available physical iPhone or iPad through `scripts/install_ios_release_candidate.sh`, with a `--dry-run` mode for checking the exact `devicectl` command before device smoke.
- Manual smoke sessions can be prepared through `scripts/manual_smoke_session_guide.sh`, which prints the current preflight, install command, checklist pointer, and scoped record-command templates without writing PASS evidence.
- Real DeepSeek translation protocol can be smoke-tested and recorded without a signed app through `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`.
- Final release completion evidence can be audited through `scripts/check_release_completion.sh`, including candidate Git commit metadata.
- Release completion and manual smoke recording accept candidate evidence from an ancestor commit only when later commits are limited to release evidence/progress documentation.
- Release completion and manual smoke recording reject candidate evidence after product, project, script, checklist, or other release-critical changes.
- Manual smoke readiness now applies candidate and DeepSeek live-smoke freshness checks before printing READY rows or recording command templates.
- Translation execution is now covered by a testable workflow object that verifies token lookup, provider invocation, recent-history persistence, missing-token failure, and non-blocking history-save warnings.
- Translation execution and DeepSeek connectivity checks trim stored DeepSeek tokens before invoking the provider, so pasted or migrated tokens with surrounding whitespace still authenticate correctly.
- UI tests now launch with an isolated in-memory data stack and per-run `UserDefaults` suite, so existing simulator or developer app data cannot make initial Library/Search/Settings assertions flaky.

Known gaps:

- CloudKit/iCloud sync is wired at the store configuration and entitlement level, but cross-device sync still needs a signed-device smoke test.
- macOS signed Release builds currently require a valid Xcode Apple Developer account session and a matching Mac App Development provisioning profile before smoke testing can start.
- iPhone/iPad translation, iOS/iPadOS import/export, iOS/iPadOS local recovery, and macOS/iOS local-only fallback smoke rows are READY to run, but still require real manual execution on the signed candidate or the documented unsigned Mac fallback path before PASS evidence can be recorded.
- macOS translation, macOS import/export, macOS local recovery, and iCloud create/delete sync smoke rows are still WAITING on a PASS macOS signed candidate.
- The release smoke checklist exists, but the manual evidence table has not been filled for the current release candidate yet.

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
- Added `scripts/manual_smoke_readiness.sh` plus regression coverage so the currently eligible manual smoke rows and optional recording command templates can be listed without writing PASS evidence.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `7d76ba8911b5`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `6303c97a9b24`.
- Extended `scripts/manual_smoke_readiness.sh --commands` to print ready-row `record_release_smoke_result.sh` command templates without printing commands for blocked rows.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `b8760d156497`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `a80d52add923`.
- Tightened `scripts/manual_smoke_readiness.sh` so stale candidate or stale DeepSeek live-smoke evidence keeps manual rows in WAITING and suppresses record command templates; reran `scripts/verify_release_readiness.sh`, including 86 macOS tests and unsigned iOS/macOS Release builds.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `fd56280d96a1`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `8046073faef3`.
- Added `scripts/manual_smoke_readiness.sh --summary` so release triage can see READY/WAITING totals and grouped WAITING reasons without parsing every row by eye.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `a645c9fb419d`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `01b09a2495ac`.
- Added `scripts/release_next_actions.sh` plus regression coverage so the next release action list can be generated from current evidence instead of being inferred manually from readiness and completion failures.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `c2a863bbade2`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `3b8578794fae`.
- Tightened Settings import handling so a keep-existing import with only skipped duplicates does not rewrite the store or record a local data change; reran `scripts/verify_release_readiness.sh`.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `fa1cc849d7ba`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `33c35ea173de`.
- Clarified Settings import status messaging so keep-existing imports that only skip duplicates say no new content was imported; reran targeted Settings import/export controller tests and `scripts/verify_release_readiness.sh`.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `1b32ffc6cfa9`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `74fb40dde8aa`.
- Added iOS simulator unit tests to `scripts/verify_release_readiness.sh`, fixed the iOS test bundle's Core Data import, and made simulator hosts default to local-only storage instead of bootstrapping CloudKit without signed iCloud entitlements.
- Reran iOS simulator tests on iPhone 17 Pro Max / iOS 26.5, targeted macOS Core Data tests, `scripts/test_verify_release_readiness.sh`, and `scripts/verify_release_readiness.sh`; the non-manual gate now covers 88 iOS simulator tests.
- Added iOS `remote-notification` background mode for CloudKit push notifications and a readiness check that verifies both `project.yml` and the generated Xcode project keep that setting.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; readiness now records iOS simulator tests and CloudKit background-mode validation, iOS candidate evidence points at commit `de1894ef8e57`, and macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `a04e8d9d3d4f`.
- Added UI-test launch isolation so `-WordSceneUITest` starts from an in-memory Core Data store and a per-run `UserDefaults` suite instead of the developer or simulator app container.
- Reran `xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5' -derivedDataPath /tmp/WordSceneUITestIsolation CODE_SIGNING_ALLOWED=NO`; 89 unit tests and 2 UI tests passed.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `b894a1f10876`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `f6985d0dfdaf` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Reran `scripts/release_next_actions.sh`; the current READY rows are `Translation loop / iPhone`, `Translation loop / iPad`, `Import/export / iOS/iPadOS`, `Local recovery / iOS/iPadOS`, and `Local-only fallback / macOS/iOS`; all macOS and iCloud rows that require a signed Mac candidate remain WAITING.
- Updated `scripts/diagnose_release_signing.sh` so `--platform macos` defaults to `/tmp/WordSceneReleaseCandidates/logs/macos-release-candidate.log`, added regression coverage, and clarified the default-log behavior in `docs/release-signing-runbook.md`.
- Reran `scripts/verify_release_readiness.sh`; script self-tests, token leak scan, 88 macOS tests, 89 iOS unit tests, 2 iOS UI tests, iOS generic build, and unsigned macOS/iOS Release builds passed.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `f381a0eaf4ae`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `5af837195bd9` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Split `scripts/check_release_completion.sh` freshness errors so stale DeepSeek live-smoke evidence reports `scripts/run_live_deepseek_translation_smoke.sh` as the rerun action instead of using candidate-build wording.
- Reran `scripts/verify_release_readiness.sh`; script self-tests, token leak scan, 88 macOS tests, 89 iOS unit tests, 2 iOS UI tests, iOS generic build, and unsigned macOS/iOS Release builds passed after the completion-audit wording split.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `9c9168a94051`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `69f5ef62aafe` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Added UI regression coverage for the language controls: source `自动检测` keeps the swap button disabled, selecting a concrete source language enables it, and repeated swaps remain reversible.
- Reran the targeted UI test `WordSceneUITests/WordSceneLaunchUITests/testLanguageControlsEnableSwapOnlyForConcreteSource` on iPhone 17 Pro Max / iOS 26.5; the test passed. A broader `xcodebuild test` attempt ran the 3 UI tests successfully but returned 65 because the app test host exited before bootstrapping, so that run is not counted as clean release evidence.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `e535f97f5474`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `8c0a0abb6276` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Added `scripts/manual_smoke_environment_preflight.sh` plus regression coverage so READY manual rows cannot be confused with actually executed device smoke; current local preflight finds the iOS candidate app, no macOS candidate app, and only an unavailable iPhone.
- Reran `scripts/test_verify_release_readiness.sh`; it exercised the new preflight test and completed the non-manual readiness gate, including macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `311770acdcda`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `33294c9bcb83` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Added `scripts/install_ios_release_candidate.sh` plus regression coverage so the current iOS release candidate can be installed to an available physical iPhone/iPad through `devicectl` without hand-assembling the command.
- Reran `scripts/test_verify_release_readiness.sh`; it exercised the iOS candidate install helper test and completed the non-manual readiness gate.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `8f1cccc5f9fd`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `f1ba360c71fd` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Added `scripts/manual_smoke_session_guide.sh` plus regression coverage so the physical-device smoke session can be prepared from one read-only command without confusing command templates with executed PASS evidence.
- Reran `scripts/test_verify_release_readiness.sh`; it exercised the manual smoke session guide test and completed the non-manual readiness gate.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `3f01ccfe4d52`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `31b46ccefaa4` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Tightened `scripts/manual_smoke_session_guide.sh` so PASS record-command templates are hidden until an installable physical iPhone or iPad is available.
- Reran `scripts/test_verify_release_readiness.sh`; it exercised the tightened manual smoke session guide and completed the non-manual readiness gate.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `97e7314f134e`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `cb97a27aeae9` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Scoped manual smoke record-command templates by executable environment so macOS-only smoke commands can be shown after macOS signing is restored without also showing iPhone/iPad commands before an installable physical device is available.
- Updated release next-action output to name the environment-scoped manual smoke command templates, matching the session guide behavior.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the new manual smoke scope filtering plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `7514ef2bc254`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `4dcbbb254807` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the release next-action wording update and completed the non-manual readiness gate.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `2b990d92f934`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `af7f995bb466` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Tightened manual smoke session guidance so the `Local-only fallback / macOS/iOS` record-command template is hidden until both an installable iOS candidate and the readiness-built unsigned macOS Release app are available.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the local-only fallback command gating plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `002cbf3c5ea4`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `8487f8f8c359` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Narrowed `scripts/manual_smoke_readiness.sh --scope ios` to iPhone/iPad-only rows, leaving the unsigned Mac plus signed iOS fallback row under `--scope local-only`.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the iOS/local-only scope split plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `fc895cd7f14e`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `2781980d190c` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Trimmed stored DeepSeek tokens in the translation workflow before provider calls and added regression coverage, closing a first-loop failure mode for tokens pasted or migrated with surrounding whitespace.
- Reran `xcodebuild test -project WordScene.xcodeproj -scheme WordSceneMac -destination 'platform=macOS' -only-testing:WordSceneMacTests/TranslationWorkflowTests -derivedDataPath /tmp/WordSceneTokenTrimMac CODE_SIGNING_ALLOWED=NO`; the 4 translation workflow tests passed.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the token-trim workflow change plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `d710ed8d47ed`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `be7a32684093` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Trimmed DeepSeek tokens defensively inside the balance client and OpenAI-compatible translation adapter so lower-level service calls match the Settings and workflow behavior.
- Reran `xcodebuild test -project WordScene.xcodeproj -scheme WordSceneMac -destination 'platform=macOS' -only-testing:WordSceneMacTests/DeepSeekBalanceResponseTests -only-testing:WordSceneMacTests/DeepSeekTranslationResponseTests -derivedDataPath /tmp/WordSceneDeepSeekTrimMac CODE_SIGNING_ALLOWED=NO`; the 11 DeepSeek service tests passed.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the service-token trim change plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `008506a60b9c`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `1be31774b14a` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Extended `scripts/manual_smoke_environment_preflight.sh` to print executable smoke environment readiness for iOS/iPadOS device smoke, signed macOS smoke, cross-platform iCloud smoke, and local-only fallback smoke.
- Reran `scripts/test_manual_smoke_environment_preflight.sh`; it covered both partial and all-ready executable environment states.
- Reran `scripts/test_verify_release_readiness.sh`; it covered the executable smoke environment preflight update plus macOS/iOS tests and unsigned Release compiles.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `1db324957ecb`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `7e5012b6b8a7` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.
- Hardened `scripts/record_release_smoke_result.sh` so PASS/FAIL manual rows require `--confirm-executed`, while BLOCKED rows can still be recorded without execution confirmation.
- Updated `scripts/manual_smoke_readiness.sh --commands` and `docs/release-smoke-test.md` so generated PASS record templates include `--confirm-executed`.
- Reran `scripts/test_record_release_smoke_result.sh`, `scripts/test_manual_smoke_readiness.sh`, `scripts/test_manual_smoke_session_guide.sh`, and `scripts/test_verify_release_readiness.sh`; the confirmation guard is covered by targeted script tests and the full non-manual gate.
- Reran `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`; iOS candidate evidence now points at commit `278a6386037b`, while macOS remains blocked by the missing Xcode account session and Mac App Development provisioning profile.
- Reran `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`; live API smoke evidence now points at commit `5b7302e9aeb4` and the real DeepSeek JSON Output path returned `你好世界` without printing the token.

Next:

- Restore a valid Xcode Apple Developer account session and Mac App Development provisioning profile for team `JU68L3U235`, then rerun `scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all`.
- Run `scripts/manual_smoke_session_guide.sh`, install the iOS candidate when target hardware is available, then run the five evidence-READY smoke rows only on available target hardware; do not record PASS rows from simulator-only checks because the release checklist requires a signed candidate or the documented unsigned Mac fallback.
- After macOS signing is restored, run the macOS translation/import-export/recovery rows and the iCloud create/delete sync rows from `docs/release-smoke-test.md`.
- Run `scripts/check_release_completion.sh` only after all required manual rows and both signed candidate builds have exactly one PASS row and no BLOCKED/FAIL rows remain.
- Keep local-only mode fully usable while sync is being prepared.
