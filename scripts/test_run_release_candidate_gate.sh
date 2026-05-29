#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BUILD_SCRIPT="$TMPDIR/fake_build_release_candidates.sh"
COLLECT_SCRIPT="$TMPDIR/fake_collect_release_candidate_evidence.sh"
READINESS_SCRIPT="$TMPDIR/fake_verify_release_readiness.sh"
EVIDENCE="$TMPDIR/evidence.md"
LOG="$TMPDIR/commands.log"

cat >"$EVIDENCE" <<'STALE_EVIDENCE'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | STALE READINESS EVIDENCE |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | STALE CANDIDATE GATE EVIDENCE |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | PRESERVED LIVE EVIDENCE |

## Manual Smoke Evidence

PRESERVED MANUAL EVIDENCE

## Release Candidate Build Evidence

STALE RELEASE EVIDENCE

## Current Build Blockers

STALE BUILD BLOCKER
STALE_EVIDENCE

cat >"$BUILD_SCRIPT" <<'FAKE_BUILD'
#!/usr/bin/env bash
set -euo pipefail
platform=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      platform="$2"
      shift 2
      ;;
    --allow-provisioning-updates)
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf 'build %s\n' "$platform" >>"$WORDSCENE_FAKE_COMMAND_LOG"
case "$platform" in
  ios)
    mkdir -p "$DERIVED_DATA_BASE/iOS/Build/Products/Release-iphoneos/Word Scene.app"
    ;;
  macos)
    echo "No profiles for 'com.erikssonhou.leximemory' were found: Xcode couldn't find any Mac App Development provisioning profiles matching 'com.erikssonhou.leximemory'." >&2
    exit 65
    ;;
  *)
    echo "unexpected platform: $platform" >&2
    exit 70
    ;;
esac
FAKE_BUILD

cat >"$COLLECT_SCRIPT" <<'FAKE_COLLECT'
#!/usr/bin/env bash
set -euo pipefail
platform=""
app=""
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      platform="$2"
      shift 2
      ;;
    --app)
      app="$2"
      shift 2
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'collect %s %s\n' "$platform" "$app" >>"$WORDSCENE_FAKE_COMMAND_LOG"
printf '| Candidate build | %s | local build host | 1 | PASS | %s |\n' "$platform" "$app" >>"$output"
FAKE_COLLECT

chmod +x "$BUILD_SCRIPT" "$COLLECT_SCRIPT"

cat >"$READINESS_SCRIPT" <<'FAKE_READINESS'
#!/usr/bin/env bash
set -euo pipefail
printf 'readiness\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_READINESS

chmod +x "$READINESS_SCRIPT"

set +e
DERIVED_DATA_BASE="$TMPDIR/DerivedData" \
  WORDSCENE_FAKE_COMMAND_LOG="$LOG" \
  WORDSCENE_BUILD_CANDIDATES_SCRIPT="$BUILD_SCRIPT" \
  WORDSCENE_COLLECT_EVIDENCE_SCRIPT="$COLLECT_SCRIPT" \
  WORDSCENE_VERIFY_RELEASE_READINESS_SCRIPT="$READINESS_SCRIPT" \
  "$ROOT/scripts/run_release_candidate_gate.sh" --platform all --evidence "$EVIDENCE" \
  >/tmp/wordscene-gate-test.out 2>/tmp/wordscene-gate-test.err
status=$?
set -e

test "$status" -eq 65
grep -qF 'readiness' "$LOG"
grep -qF 'build macos' "$LOG"
grep -qF 'build ios' "$LOG"
grep -qF 'collect ios' "$LOG"
if grep -qF 'STALE READINESS EVIDENCE' "$EVIDENCE"; then
  echo "release candidate gate should replace stale readiness evidence after rerunning readiness checks" >&2
  exit 1
fi
if grep -qF 'STALE CANDIDATE GATE EVIDENCE' "$EVIDENCE"; then
  echo "release candidate gate should replace stale candidate gate evidence after rerunning candidate builds" >&2
  exit 1
fi
if grep -qF 'STALE RELEASE EVIDENCE' "$EVIDENCE"; then
  echo "release candidate gate should replace stale evidence instead of appending to it" >&2
  exit 1
fi
if grep -qF 'STALE BUILD BLOCKER' "$EVIDENCE"; then
  echo "release candidate gate should replace stale build blockers instead of preserving them" >&2
  exit 1
fi
grep -qF 'PRESERVED MANUAL EVIDENCE' "$EVIDENCE"
grep -qF 'PRESERVED LIVE EVIDENCE' "$EVIDENCE"
grep -qF '## Non-Manual Release Gate' "$EVIDENCE"
grep -qF '| Readiness script | macOS + iOS generic | local build host | 1 | PASS | scripts/verify_release_readiness.sh passed script syntax checks, shell regression tests, git diff --check, token leak scan, XcodeGen version-marker scan, macOS tests, iOS generic build, and unsigned macOS/iOS Release compiles. |' "$EVIDENCE"
grep -qF '| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | scripts/run_release_candidate_gate.sh recorded release readiness, candidate build evidence, and signing blockers; rerun after resolving the blocked platform. |' "$EVIDENCE"
grep -qF '| Candidate build | ios | local build host | 1 | PASS |' "$EVIDENCE"
grep -qF '| Candidate build | macOS | local build host | 1 | BLOCKED |' "$EVIDENCE"
grep -qF 'Signing diagnosis / macOS / BLOCKED' "$EVIDENCE"
grep -qF 'Mac App Development provisioning profile is missing for com.erikssonhou.leximemory' "$EVIDENCE"
