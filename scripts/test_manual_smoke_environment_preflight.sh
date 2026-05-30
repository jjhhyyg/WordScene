#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
EVIDENCE="$TMPDIR/release-smoke-evidence.md"
CANDIDATE_ROOT="$TMPDIR/candidates"
DEVICE_LIST="$TMPDIR/devices.txt"

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
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   available     iPhone 17 Pro Max
Lab iPad         Lab-iPad.coredevice.local        00000000-0000-0000-0000-000000000002   unavailable   iPad Pro 11-inch
DEVICES

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight.out"

grep -qF 'Manual Smoke Environment Preflight' "$TMPDIR/preflight.out"
grep -qF -- '- Ready rows: 5' "$TMPDIR/preflight.out"
grep -qF -- '- Waiting rows: 5' "$TMPDIR/preflight.out"
grep -qF -- '- iOS release candidate app: FOUND' "$TMPDIR/preflight.out"
grep -qF -- '- macOS release candidate app: MISSING' "$TMPDIR/preflight.out"
grep -qF 'Moses iPhone' "$TMPDIR/preflight.out"
grep -qF 'Lab iPad' "$TMPDIR/preflight.out"
grep -qF 'Do not record PASS for iPhone/iPad rows until the target physical device has actually run the checklist.' "$TMPDIR/preflight.out"
