#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
EVIDENCE="$TMPDIR/release-smoke-evidence.md"
CANDIDATE_ROOT="$TMPDIR/candidates"
DEVICE_LIST="$TMPDIR/devices.txt"
UNSIGNED_MAC_APP="$TMPDIR/unsigned/Word Scene.app"

cat >"$EVIDENCE" <<EVIDENCE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | readiness passed |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | macOS signing blocked |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live smoke passed. Git commit \`$CURRENT_COMMIT\`. |

## Release Candidate Build Blocker

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | BLOCKED | missing profile |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | signed iOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
EVIDENCE_MD

mkdir -p "$CANDIDATE_ROOT/iOS/Build/Products/Release-iphoneos/Word Scene.app"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
Lab iPhone       Lab-iPhone.coredevice.local      00000000-0000-0000-0000-000000000001   unavailable   iPhone 17 Pro Max
DEVICES

"$ROOT/scripts/release_next_actions.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/actions.out"

grep -qF 'Release Next Actions' "$TMPDIR/actions.out"
grep -qF '1. Restore macOS signing before macOS and iCloud smoke.' "$TMPDIR/actions.out"
grep -qF 'scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all' "$TMPDIR/actions.out"
grep -qF '2. READY manual smoke rows allowed by current evidence:' "$TMPDIR/actions.out"
grep -qF -- '- Translation loop / iPhone' "$TMPDIR/actions.out"
grep -qF -- '- Import/export / iOS/iPadOS' "$TMPDIR/actions.out"
grep -qF -- '- Local-only fallback / macOS/iOS' "$TMPDIR/actions.out"
grep -qF '3. Executable smoke environments right now:' "$TMPDIR/actions.out"
grep -qF -- '- iOS/iPadOS device smoke: WAIT - requires an available physical iPhone/iPad and the iOS candidate app' "$TMPDIR/actions.out"
grep -qF -- '- macOS signed-candidate smoke: WAIT - requires the signed macOS candidate app' "$TMPDIR/actions.out"
grep -qF -- '- Cross-platform iCloud smoke: WAIT - requires an available physical iPhone/iPad plus signed iOS and macOS candidates' "$TMPDIR/actions.out"
grep -qF -- '- Local-only fallback smoke: WAIT - requires an available physical iPhone/iPad, the iOS candidate app, and the unsigned macOS Release app' "$TMPDIR/actions.out"
grep -qF '4. Before recording PASS, confirm executable devices with scripts/manual_smoke_environment_preflight.sh.' "$TMPDIR/actions.out"
grep -qF '5. When a physical iPhone or iPad is available, install the iOS candidate with scripts/install_ios_release_candidate.sh before running device smoke.' "$TMPDIR/actions.out"
grep -qF '6. Use scripts/manual_smoke_session_guide.sh to print the preflight, install command, checklist pointer, and environment-scoped record-command templates in one place.' "$TMPDIR/actions.out"
grep -qF '7. Do not call the release complete until scripts/check_release_completion.sh passes.' "$TMPDIR/actions.out"
