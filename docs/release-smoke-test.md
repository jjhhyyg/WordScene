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
  leak scanning, privacy manifest validation, required-reason API scanning,
  privacy surface validation, CloudKit background-mode validation, XcodeGen
  version-marker scanning, macOS tests, iOS simulator tests, iOS generic build,
  and unsigned macOS/iOS Release compiles.
- Use `scripts/run_release_candidate_gate.sh --allow-provisioning-updates` to
  rerun readiness checks, refresh the non-manual gate evidence, build each
  release candidate, and append build evidence or blocker rows to
  `docs/release-smoke-evidence.md`. Candidate build evidence must include the
  Git commit used to produce the app bundle. The gate requires a clean git
  worktree so the generated evidence can be reproduced from that commit.
- Run `scripts/check_release_completion.sh` only after recording all candidate
  build and manual smoke evidence. It must pass before calling the release
  complete or the cross-platform product loop genuinely usable. The candidate
  build Git commit recorded in evidence must either match the current repository
  HEAD or be an ancestor with only evidence/progress documentation changed after
  it. Rerun the candidate gate after any product, project, script, checklist, or
  release-critical code change.
- Run `scripts/manual_smoke_readiness.sh` after candidate and live API evidence
  are refreshed to see which manual rows can be tested now. Add `--commands` to
  print `scripts/record_release_smoke_result.sh` templates for READY rows. It
  applies the same candidate/live-smoke freshness checks as manual evidence
  recording, so stale evidence prints WAITING instead of record commands. It is
  read-only and does not record PASS evidence. Add `--summary` to append READY
  and WAITING counts plus grouped WAITING reasons for release triage. Add
  `--scope ios` or `--scope ios-device` for iPhone/iPad-only rows,
  `--scope macos` for signed Mac rows, `--scope cross-platform` for rows that
  require both signed iOS and signed macOS candidates, or `--scope local-only`
  for the unsigned Mac plus signed iOS fallback row.
- Run `scripts/release_next_actions.sh` when deciding what to do next. It wraps
  the same readiness rules into an ordered action list, including the macOS
  signing recovery step, READY manual rows, and the final completion gate.
- Run `scripts/manual_smoke_environment_preflight.sh` before recording PASS
  rows. It checks the current evidence readiness, candidate app bundle paths,
  physical iPhone/iPad availability reported by `devicectl`, and the resulting
  executable smoke environments. READY rows are only permission to run and
  record a row; they are not proof that the target device checklist has been
  executed.
- When a target iPhone or iPad is available, install the current iOS candidate
  with `scripts/install_ios_release_candidate.sh`. Add `--device <identifier>`
  to target a specific device, or `--dry-run` to print the `devicectl` command
  before installing.
- Use `scripts/manual_smoke_session_guide.sh` to print the current preflight,
  iOS install command, checklist pointer, and scoped record-command templates in
  one place. It is read-only and does not record PASS rows. It hides PASS
  record command templates until the matching executable candidate environment
  is available, and it does not print iPhone/iPad templates just because macOS
  smoke is runnable. The local-only fallback template is shown only when an
  iOS candidate can be installed and the readiness-built unsigned macOS Release
  app is still present; pass `--unsigned-macos-app <path>` if that artifact was
  moved from the default `/tmp/WordSceneVerifyReleaseMac` location.
- Optionally run
  `scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md`
  before signed app smoke testing to verify and record the current DeepSeek
  token, JSON Output request, and structured prompt payload against the real API.
  It reads the token from `.local/deepseek-token` by default and does not print
  the token.
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
the table format stays consistent. The script only accepts the canonical
manual `Area` and `Platform` pairs listed in the template below, so typos such
as `iPadOS` instead of `iOS/iPadOS` are rejected before they create evidence
rows that the completion audit cannot count. It also requires release candidate
metadata for the current repository state before writing manual rows. Candidate
metadata may point to an ancestor commit only when the newer commits are limited
to evidence/progress documentation such as `docs/release-smoke-evidence.md` and
`docs/implementation-plan.md`; run the candidate gate again after any product,
project, script, checklist, or release-critical code change and before recording
smoke results.
Each manual row must also have PASS candidate build evidence for the platform it
tests: macOS rows require a macOS candidate, iPhone/iPad rows require an iOS
candidate, and iCloud cross-platform rows require both. The local-only fallback
row may be recorded with PASS iOS candidate evidence plus the readiness-covered
unsigned macOS Release build, because that scenario intentionally verifies
unsigned/local-only behavior on Mac.
Recording `PASS` or `FAIL` also requires `--confirm-executed`; only add it
after the checklist was actually run on the stated device or environment.
Recording the same `Area` and `Platform` again replaces the stale manual row,
so a retest can move a row from `BLOCKED` or `FAIL` to the current result
without leaving contradictory evidence behind:

```bash
scripts/record_release_smoke_result.sh \
  --evidence docs/release-smoke-evidence.md \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
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

After all rows are recorded, run:

```bash
scripts/check_release_completion.sh
```

The script fails if any required row does not have exactly one PASS entry, if
the evidence table structure is malformed, if candidate Git commit metadata is
missing, if the candidate commit is not an ancestor of the current repository
HEAD, if release-critical files changed after the candidate build, or if any
BLOCKED/FAIL row is still present in `docs/release-smoke-evidence.md`.
