#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BUILD_SCRIPT="$TMPDIR/fake_build_release_candidates.sh"
COLLECT_SCRIPT="$TMPDIR/fake_collect_release_candidate_evidence.sh"
READINESS_SCRIPT="$TMPDIR/fake_verify_release_readiness.sh"
EVIDENCE="$TMPDIR/evidence.md"
LOG="$TMPDIR/commands.log"
DIRTY_BIN="$TMPDIR/dirty-bin"
DIRTY_EVIDENCE="$TMPDIR/dirty-evidence.md"
DIRTY_LOG="$TMPDIR/dirty-commands.log"

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

mkdir -p "$DIRTY_BIN"
cat >"$DIRTY_BIN/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"status --porcelain"* ]]; then
  printf ' M WordScene/Sources/Shared/App/WordSceneApp.swift\n'
  exit 0
fi
exec /usr/bin/git "$@"
FAKE_GIT
chmod +x "$DIRTY_BIN/git"

set +e
PATH="$DIRTY_BIN:$PATH" \
DERIVED_DATA_BASE="$TMPDIR/DirtyDerivedData" \
  WORDSCENE_FAKE_COMMAND_LOG="$DIRTY_LOG" \
  WORDSCENE_BUILD_CANDIDATES_SCRIPT="$BUILD_SCRIPT" \
  WORDSCENE_COLLECT_EVIDENCE_SCRIPT="$COLLECT_SCRIPT" \
  WORDSCENE_VERIFY_RELEASE_READINESS_SCRIPT="$READINESS_SCRIPT" \
  "$ROOT/scripts/run_release_candidate_gate.sh" --platform all --evidence "$DIRTY_EVIDENCE" \
  >/tmp/wordscene-dirty-gate-test.out 2>/tmp/wordscene-dirty-gate-test.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Release candidate gate requires a clean git worktree.' /tmp/wordscene-dirty-gate-test.err
if [[ -f "$DIRTY_LOG" ]]; then
  echo "release candidate gate should not run readiness or builds with a dirty worktree" >&2
  exit 1
fi
if [[ -f "$DIRTY_EVIDENCE" ]]; then
  echo "release candidate gate should not write evidence with a dirty worktree" >&2
  exit 1
fi

set +e
DERIVED_DATA_BASE="$TMPDIR/DerivedData" \
  WORDSCENE_FAKE_COMMAND_LOG="$LOG" \
  WORDSCENE_SKIP_DIRTY_RELEASE_GATE_CHECK=1 \
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
grep -qF '| Readiness script | macOS + iOS generic | local build host | 1 | PASS | scripts/internal/verify_release_readiness.sh passed script syntax checks, shell regression tests, git diff --check, token leak scan, privacy manifest validation, required-reason API scan, privacy surface validation, CloudKit background-mode validation, XcodeGen version-marker scan, macOS tests, iOS simulator tests, iOS generic build, and unsigned macOS/iOS Release compiles. |' "$EVIDENCE"
grep -qF '| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | scripts/run_release_candidate_gate.sh recorded release readiness, candidate build evidence, and signing blockers; rerun after resolving the blocked platform. |' "$EVIDENCE"
grep -qF '| Candidate build | ios | local build host | 1 | PASS |' "$EVIDENCE"
grep -qF '| Candidate build | macOS | local build host | 1 | BLOCKED |' "$EVIDENCE"
grep -qF 'Signing diagnosis / macOS / BLOCKED' "$EVIDENCE"
grep -qF 'Mac App Development provisioning profile is missing for com.erikssonhou.leximemory' "$EVIDENCE"

IOS_ONLY_EVIDENCE="$TMPDIR/ios-only-evidence.md"
IOS_ONLY_LOG="$TMPDIR/ios-only-commands.log"

cat >"$IOS_ONLY_EVIDENCE" <<'IOS_ONLY_STALE_EVIDENCE'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | STALE READINESS EVIDENCE |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | STALE MACOS BLOCKER |
| Candidate gate | iOS | local build host | 1 | PASS | STALE IOS GATE |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | PRESERVED LIVE EVIDENCE |

## Release Candidate Build Blocker

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | BLOCKED | PRESERVED MACOS BLOCKER |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | STALE IOS EVIDENCE |
IOS_ONLY_STALE_EVIDENCE

DERIVED_DATA_BASE="$TMPDIR/IOSOnlyDerivedData" \
  WORDSCENE_FAKE_COMMAND_LOG="$IOS_ONLY_LOG" \
  WORDSCENE_SKIP_DIRTY_RELEASE_GATE_CHECK=1 \
  WORDSCENE_BUILD_CANDIDATES_SCRIPT="$BUILD_SCRIPT" \
  WORDSCENE_COLLECT_EVIDENCE_SCRIPT="$COLLECT_SCRIPT" \
  WORDSCENE_VERIFY_RELEASE_READINESS_SCRIPT="$READINESS_SCRIPT" \
  "$ROOT/scripts/run_release_candidate_gate.sh" --platform ios --evidence "$IOS_ONLY_EVIDENCE" \
  >/tmp/wordscene-ios-only-gate-test.out 2>/tmp/wordscene-ios-only-gate-test.err

grep -qF 'readiness' "$IOS_ONLY_LOG"
grep -qF 'build ios' "$IOS_ONLY_LOG"
grep -qF 'collect ios' "$IOS_ONLY_LOG"
if grep -qF 'build macos' "$IOS_ONLY_LOG"; then
  echo "ios-only release candidate gate should not build macOS" >&2
  exit 1
fi
if grep -qF 'STALE READINESS EVIDENCE' "$IOS_ONLY_EVIDENCE"; then
  echo "ios-only release candidate gate should replace stale readiness evidence" >&2
  exit 1
fi
if grep -qF 'STALE IOS GATE' "$IOS_ONLY_EVIDENCE"; then
  echo "ios-only release candidate gate should replace stale iOS gate evidence" >&2
  exit 1
fi
if grep -qF 'STALE IOS EVIDENCE' "$IOS_ONLY_EVIDENCE"; then
  echo "ios-only release candidate gate should replace stale iOS candidate evidence" >&2
  exit 1
fi
grep -qF '| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | STALE MACOS BLOCKER |' "$IOS_ONLY_EVIDENCE"
grep -qF '| Candidate gate | iOS | local build host | 1 | PASS |' "$IOS_ONLY_EVIDENCE"
grep -qF '| Candidate build | macOS | local build host | 1 | BLOCKED | PRESERVED MACOS BLOCKER |' "$IOS_ONLY_EVIDENCE"
grep -qF '| Candidate build | ios | local build host | 1 | PASS |' "$IOS_ONLY_EVIDENCE"
