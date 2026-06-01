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

"$ROOT/scripts/manual_smoke_session_guide.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/guide.out"

grep -qF 'Manual Smoke Session Guide' "$TMPDIR/guide.out"
grep -qF 'Manual Smoke Environment Preflight' "$TMPDIR/guide.out"
grep -qF 'scripts/install_ios_release_candidate.sh --device 00000000-0000-0000-0000-000000000001' "$TMPDIR/guide.out"
grep -qF 'scripts/record_release_smoke_result.sh \' "$TMPDIR/guide.out"
grep -qF 'iOS/iPadOS device rows:' "$TMPDIR/guide.out"
grep -qF -- '--area "Translation loop"' "$TMPDIR/guide.out"
grep -qF -- '--platform "iPhone"' "$TMPDIR/guide.out"
grep -qF "Local-only fallback command is hidden until the unsigned macOS Release app is available: $UNSIGNED_MAC_APP" "$TMPDIR/guide.out"
if grep -qF -- '--platform "macOS/iOS"' "$TMPDIR/guide.out"; then
  echo "iOS-only guide must not print local-only fallback commands before the unsigned Mac app exists." >&2
  exit 1
fi

mkdir -p "$UNSIGNED_MAC_APP"

"$ROOT/scripts/manual_smoke_session_guide.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/local-only-guide.out"

grep -qF 'Local-only fallback row:' "$TMPDIR/local-only-guide.out"
grep -qF 'Manual Smoke Readiness (local-only scope)' "$TMPDIR/local-only-guide.out"
grep -qF '  --platform "macOS/iOS" \' "$TMPDIR/local-only-guide.out"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State       Model
--------------   ------------------------------   ------------------------------------   ---------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   connected   iPhone 17 Pro Max
DEVICES

"$ROOT/scripts/manual_smoke_session_guide.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/connected-guide.out"

grep -qF 'scripts/install_ios_release_candidate.sh --device 00000000-0000-0000-0000-000000000001' "$TMPDIR/connected-guide.out"
grep -qF 'iOS/iPadOS device rows:' "$TMPDIR/connected-guide.out"

rm -rf "$CANDIDATE_ROOT/iOS"
cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   unavailable   iPhone 17 Pro Max
DEVICES

"$ROOT/scripts/manual_smoke_session_guide.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/waiting-guide.out"

grep -qF 'WAIT: An available physical iPhone/iPad and iOS candidate app are required before install.' "$TMPDIR/waiting-guide.out"
grep -qF 'PASS record commands are hidden until an executable candidate environment is available.' "$TMPDIR/waiting-guide.out"
if grep -qF 'scripts/record_release_smoke_result.sh \' "$TMPDIR/waiting-guide.out"; then
  echo "Waiting guide must not print PASS record commands." >&2
  exit 1
fi

cat >"$EVIDENCE" <<EVIDENCE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | readiness passed |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | iOS unavailable |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live smoke passed. Git commit \`$CURRENT_COMMIT\`. |

## Release Candidate Build Blocker

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | BLOCKED | unavailable device |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | signed macOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
EVIDENCE_MD

mkdir -p "$CANDIDATE_ROOT/macOS/Build/Products/Release/Word Scene.app"

"$ROOT/scripts/manual_smoke_session_guide.sh" \
  --evidence "$EVIDENCE" \
  --candidate-root "$CANDIDATE_ROOT" \
  --unsigned-macos-app "$UNSIGNED_MAC_APP" \
  --device-list "$DEVICE_LIST" >"$TMPDIR/macos-only-guide.out"

grep -qF 'Record only smoke rows that were actually executed and passed:' "$TMPDIR/macos-only-guide.out"
grep -qF 'macOS signed-candidate rows:' "$TMPDIR/macos-only-guide.out"
grep -qF 'Manual Smoke Readiness (macos scope)' "$TMPDIR/macos-only-guide.out"
grep -qF '  --platform "macOS" \' "$TMPDIR/macos-only-guide.out"
if grep -qF '  --platform "iPhone" \' "$TMPDIR/macos-only-guide.out"; then
  echo "macOS-only guide must not print iPhone record commands without an installable device." >&2
  exit 1
fi
