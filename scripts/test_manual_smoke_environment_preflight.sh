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
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   available     iPhone 17 Pro Max
Lab iPad         Lab-iPad.coredevice.local        00000000-0000-0000-0000-000000000002   unavailable   iPad Pro 11-inch
DEVICES

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight.out"

grep -qF 'Manual Smoke Environment Preflight' "$TMPDIR/preflight.out"
grep -qF -- '- Ready rows: 5' "$TMPDIR/preflight.out"
grep -qF -- '- Waiting rows: 5' "$TMPDIR/preflight.out"
grep -qF -- '- iOS release candidate app: FOUND' "$TMPDIR/preflight.out"
grep -qF -- '- macOS release candidate app: MISSING' "$TMPDIR/preflight.out"
grep -qF -- '- unsigned macOS Release app for local-only fallback: MISSING' "$TMPDIR/preflight.out"
grep -qF 'Moses iPhone' "$TMPDIR/preflight.out"
grep -qF 'Lab iPad' "$TMPDIR/preflight.out"
grep -qF -- '- iOS/iPadOS device smoke: READY - requires an available physical iPhone/iPad and the iOS candidate app' "$TMPDIR/preflight.out"
grep -qF -- '- macOS signed-candidate smoke: WAIT - requires the signed macOS candidate app' "$TMPDIR/preflight.out"
grep -qF -- '- Cross-platform iCloud smoke: WAIT - requires an available physical iPhone/iPad plus signed iOS and macOS candidates' "$TMPDIR/preflight.out"
grep -qF -- '- Local-only fallback smoke: WAIT - requires an available physical iPhone/iPad, the iOS candidate app, and the unsigned macOS Release app' "$TMPDIR/preflight.out"
grep -qF 'Do not record PASS for iPhone/iPad rows until the target physical device has actually run the checklist.' "$TMPDIR/preflight.out"
grep -qF 'Do not record the local-only fallback row until both the iOS candidate is installed on a physical device and the unsigned macOS Release app has actually run the checklist.' "$TMPDIR/preflight.out"
grep -qF 'Next environment actions:' "$TMPDIR/preflight.out"
grep -qF 'Physical iPhone/iPad detected as available or connected; install the iOS candidate before recording device smoke.' "$TMPDIR/preflight.out"
grep -qF 'Signed macOS candidate app is missing; restore the Xcode account/profile for team JU68L3U235 before macOS and iCloud smoke.' "$TMPDIR/preflight.out"

mkdir -p "$CANDIDATE_ROOT/macOS/Build/Products/Release/Word Scene.app"
mkdir -p "$UNSIGNED_MAC_APP"

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight-all-ready.out"

grep -qF -- '- iOS/iPadOS device smoke: READY - requires an available physical iPhone/iPad and the iOS candidate app' "$TMPDIR/preflight-all-ready.out"
grep -qF -- '- macOS signed-candidate smoke: READY - requires the signed macOS candidate app' "$TMPDIR/preflight-all-ready.out"
grep -qF -- '- Cross-platform iCloud smoke: READY - requires an available physical iPhone/iPad plus signed iOS and macOS candidates' "$TMPDIR/preflight-all-ready.out"
grep -qF -- '- Local-only fallback smoke: READY - requires an available physical iPhone/iPad, the iOS candidate app, and the unsigned macOS Release app' "$TMPDIR/preflight-all-ready.out"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State       Model
--------------   ------------------------------   ------------------------------------   ---------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   connected   iPhone 17 Pro Max
DEVICES

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight-connected-device.out"

grep -qF 'Moses iPhone' "$TMPDIR/preflight-connected-device.out"
grep -qF -- '- iOS/iPadOS device smoke: READY - requires an available physical iPhone/iPad and the iOS candidate app' "$TMPDIR/preflight-connected-device.out"
grep -qF 'Physical iPhone/iPad detected as available or connected; install the iOS candidate before recording device smoke.' "$TMPDIR/preflight-connected-device.out"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   unavailable   iPhone 17 Pro Max
DEVICES

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight-unavailable-device.out"

grep -qF 'A physical iPhone/iPad is visible but unavailable; unlock it, trust this Mac, confirm Developer Mode, and reconnect or re-pair it before smoke.' "$TMPDIR/preflight-unavailable-device.out"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
DEVICES

"$ROOT/scripts/manual_smoke_environment_preflight.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/preflight-no-device.out"

grep -qF 'No physical iPhone/iPad is visible; connect or pair a real device. Simulator runs do not satisfy release smoke evidence.' "$TMPDIR/preflight-no-device.out"
