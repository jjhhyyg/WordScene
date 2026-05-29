# WordScene Release Smoke Test

This checklist is the manual gate before calling the current product loop usable
across iPhone, iPad, and macOS. Record device names, OS versions, build number,
and pass/fail notes for each run.

## Preconditions

- Use a signed build with the production bundle identifier.
- Generate release candidate builds with
  `scripts/build_release_candidates.sh --allow-provisioning-updates` after Xcode
  is signed in to the Apple Developer account. If provisioning has already been
  prepared locally, the flag can be omitted. Use `--platform ios` or
  `--platform macos` only when recording a platform-specific build blocker.
- If macOS signing fails with missing Xcode account or Mac App Development
  profile errors, follow `docs/release-signing-runbook.md` before changing
  project settings.
- Run `scripts/verify_release_readiness.sh` before manual smoke testing. It
  covers script syntax, release evidence script tests, `git diff --check`, token
  leak scanning, XcodeGen version-marker scanning, macOS tests, iOS generic
  build, and unsigned macOS/iOS Release compiles.
- Use `scripts/run_release_candidate_gate.sh --allow-provisioning-updates` to
  build each release candidate and append build evidence or blocker rows to
  `docs/release-smoke-evidence.md`.
- Optionally run `scripts/run_live_deepseek_translation_smoke.sh` before signed
  app smoke testing to verify the current DeepSeek token, JSON Output request,
  and structured prompt payload against the real API. It reads the token from
  `.local/deepseek-token` by default and does not print the token.
- Use the same Apple ID on all devices used for iCloud sync testing.
- Confirm iCloud Drive and CloudKit are enabled for the Apple ID.
- Keep the DeepSeek API token local to each device; do not expect it to sync.
- Start with network access enabled, then repeat the local-only checks offline.
- Keep Console or Xcode logs open only for unexpected app errors. Platform logs
  such as haptic library misses, ViewBridge cancellation, or AppIntents linkd
  failures are not product failures unless the UI breaks or the app crashes.

## Core Translation Loop

Run on macOS, iPhone, and iPad.

1. Open Settings.
2. Save the DeepSeek token.
3. Tap test connection.
4. Open Translate.
5. Translate `hello world` from auto-detect to Chinese.
6. Verify the result panel leaves the loading state and shows translated text.
7. Favorite the result.
8. Verify the item appears in Library.
9. Manually add one Library item without translating.
10. Search for `hello`, `你好`, the manually added text, and the Chinese pinyin
    form if applicable.
11. Relaunch the app and verify history, favorite state, manual item, and saved
    token status.

Expected result:

- Translation works after token setup.
- Missing-token, loading, success, and failure states remain readable.
- Favorites and recent history survive relaunch.
- Manual Library items can be created without a network translation request.
- The same workflow is usable on all three platforms without layout overlap.

## Language Controls

Run on at least one iPhone and one Mac window width below the three-column layout.

1. Set source language to auto-detect.
2. Verify the swap button is disabled.
3. Set source and target to concrete languages.
4. Swap languages twice.
5. Translate with the swapped direction.

Expected result:

- Auto-detect cannot be swapped into an invalid empty target language.
- Concrete language swaps are reversible.

## Import And Export

Run once on macOS and once on iOS or iPadOS.

1. Create at least two saved library items.
2. Export from Settings.
3. Open the JSON file and confirm it includes `export_schema_version`,
   `checksum`, and `items`.
4. Confirm the export does not include the configured API token.
5. Delete or modify one local item.
6. Import the exported file.
7. Verify duplicate handling reports imported, replaced, and skipped counts
   accurately.
8. Verify Library and Search reflect the imported state without relaunching.

Expected result:

- Export produces `memory-book-export-YYYYMMDD.json`.
- Import rejects modified files with checksum errors.
- Import does not wipe unrelated local state.
- Already loaded Library and Search views refresh after import.
- API token is not present in exported metadata.

## Local Recovery

Run on macOS first, then repeat on iOS or iPadOS after file export is confirmed.

1. Open Settings.
2. Export the old local cache backup.
3. Verify the backup JSON contains only known legacy local cache documents.
4. Cancel the reset and verify no data changes.
5. Run reset.
6. Verify current Core Data-backed Library and History remain usable.

Expected result:

- Recovery actions are scoped to early local documents only.
- Backup export works before destructive reset.
- Reset does not remove the API token or unrelated preferences.

## iCloud Sync

Run with two signed devices on the same Apple ID. Prefer one iPhone and one Mac;
repeat with iPad before release if possible.

1. Install the same signed build on both devices.
2. Launch both devices and open Settings.
3. Verify Settings shows iCloud sync configured rather than local-only.
4. On Device A, create and favorite a translation memory item.
5. Wait for Settings to show a recent CloudKit export or import event.
6. On Device B, wait for the item to appear in Library and Search.
7. Relaunch Device B and verify the item remains present.
8. On Device B, delete the item.
9. Wait for Device A to remove the item from Library and Search.
10. Relaunch both devices and verify the deletion remains.
11. Confirm Device B still requires its own DeepSeek token before translating.

Expected result:

- Saved items sync eventually through iCloud.
- Deletes sync eventually and do not resurrect after relaunch.
- Sync status surfaces waiting, success, or failure without claiming real-time
  guarantees.
- API tokens do not sync through iCloud or export/import.

## Offline And Local-Only Fallback

Run on one Mac unsigned build and one iOS device with network disabled.

1. Launch the app.
2. Verify local-only mode is explicit when CloudKit entitlement or network state
   prevents sync.
3. Verify Settings shows the current network availability state.
4. Manually create, search, and delete a local item from Library.
5. Relaunch and verify local data remains usable.
6. Re-enable network and verify the app does not crash or silently discard local
   work.

Expected result:

- Local-only mode is usable and clearly labelled.
- No sync failure blocks local translation memory usage.

## Evidence Template

Use this table for each release candidate. Build metadata and blocker evidence
for the current candidate is recorded in `docs/release-smoke-evidence.md`.
Prefer recording manual rows with `scripts/record_release_smoke_result.sh` so
the table format stays consistent:

```bash
scripts/record_release_smoke_result.sh \
  --evidence docs/release-smoke-evidence.md \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --notes "Saved token, translated hello world, history survived relaunch."
```

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS |  |  |  |  |
| Candidate build | iOS |  |  |  |  |
| Translation loop | macOS |  |  |  |  |
| Translation loop | iPhone |  |  |  |  |
| Translation loop | iPad |  |  |  |  |
| Import/export | macOS |  |  |  |  |
| Import/export | iOS/iPadOS |  |  |  |  |
| Local recovery | macOS |  |  |  |  |
| Local recovery | iOS/iPadOS |  |  |  |  |
| iCloud create sync | iPhone + macOS |  |  |  |  |
| iCloud delete sync | iPhone + macOS |  |  |  |  |
| Local-only fallback | macOS/iOS |  |  |  |  |
