#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BUILD_SCRIPT="$TMPDIR/fake_build_release_candidates.sh"
COLLECT_SCRIPT="$TMPDIR/fake_collect_release_candidate_evidence.sh"
EVIDENCE="$TMPDIR/evidence.md"
LOG="$TMPDIR/commands.log"

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
    echo "No profiles for com.erikssonhou.leximemory" >&2
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

set +e
DERIVED_DATA_BASE="$TMPDIR/DerivedData" \
  WORDSCENE_FAKE_COMMAND_LOG="$LOG" \
  WORDSCENE_BUILD_CANDIDATES_SCRIPT="$BUILD_SCRIPT" \
  WORDSCENE_COLLECT_EVIDENCE_SCRIPT="$COLLECT_SCRIPT" \
  "$ROOT/scripts/run_release_candidate_gate.sh" --platform all --evidence "$EVIDENCE" \
  >/tmp/wordscene-gate-test.out 2>/tmp/wordscene-gate-test.err
status=$?
set -e

test "$status" -eq 65
grep -qF 'build macos' "$LOG"
grep -qF 'build ios' "$LOG"
grep -qF 'collect ios' "$LOG"
grep -qF '| Candidate build | ios | local build host | 1 | PASS |' "$EVIDENCE"
grep -qF '| Candidate build | macOS | local build host | 1 | BLOCKED |' "$EVIDENCE"
grep -qF 'No profiles for com.erikssonhou.leximemory' "$EVIDENCE"
