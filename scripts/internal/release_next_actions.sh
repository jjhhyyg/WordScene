#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
CANDIDATE_ROOT="/tmp/WordSceneReleaseCandidates"
UNSIGNED_MACOS_RELEASE_APP="/tmp/WordSceneVerifyReleaseMac/Build/Products/Release/Word Scene.app"
DEVICE_LIST_FILE=""

usage() {
  echo "Usage: $0 [--evidence <markdown>] [--candidate-root <path>] [--unsigned-macos-app <Word Scene.app>] [--device-list <path>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      EVIDENCE_FILE="$2"
      shift 2
      ;;
    --candidate-root)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      CANDIDATE_ROOT="$2"
      shift 2
      ;;
    --unsigned-macos-app)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      UNSIGNED_MACOS_RELEASE_APP="$2"
      shift 2
      ;;
    --device-list)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DEVICE_LIST_FILE="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ ! -f "$EVIDENCE_FILE" ]]; then
  echo "Release evidence file not found: $EVIDENCE_FILE" >&2
  exit 1
fi

readiness="$("$ROOT/scripts/internal/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --summary)"
preflight_args=(
  --evidence "$EVIDENCE_FILE"
  --candidate-root "$CANDIDATE_ROOT"
  --unsigned-macos-app "$UNSIGNED_MACOS_RELEASE_APP"
)
if [[ -n "$DEVICE_LIST_FILE" ]]; then
  preflight_args+=(--device-list "$DEVICE_LIST_FILE")
fi
preflight="$("$ROOT/scripts/internal/manual_smoke_environment_preflight.sh" "${preflight_args[@]}")"
ready_rows="$(
  printf '%s\n' "$readiness" |
    awk '/^READY / {
      sub(/^READY /, "")
      print
    }'
)"
executable_environments="$(
  printf '%s\n' "$preflight" |
    awk '
      /^Executable smoke environments:$/ {
        capture = 1
        next
      }
      capture == 1 && /^$/ {
        exit
      }
      capture == 1 {
        print
      }
    '
)"
environment_actions="$(
  printf '%s\n' "$preflight" |
    awk '
      /^Next environment actions:$/ {
        capture = 1
        next
      }
      capture == 1 && /^$/ {
        exit
      }
      capture == 1 {
        print
      }
    '
)"

echo "Release Next Actions"

if printf '%s\n' "$readiness" | grep -qF 'missing PASS candidate build: macOS'; then
  cat <<'ACTIONS'
1. Restore macOS signing before macOS and iCloud smoke.
   - Open Xcode Settings > Accounts and add or re-authenticate the Apple ID for team JU68L3U235.
   - Rerun scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all.
ACTIONS
else
  echo "1. macOS candidate blocker is not reported by readiness."
fi

echo "2. READY manual smoke rows allowed by current evidence:"
if [[ -n "$ready_rows" ]]; then
  while IFS= read -r row; do
    [[ -n "$row" ]] && printf '   - %s\n' "$row"
  done <<<"$ready_rows"
else
  echo "   - none"
fi

echo "3. Executable smoke environments right now:"
if [[ -n "$executable_environments" ]]; then
  printf '%s\n' "$executable_environments" | sed 's/^/   /'
else
  echo "   - unknown; rerun scripts/internal/manual_smoke_environment_preflight.sh"
fi
echo "4. Environment actions before smoke:"
if [[ -n "$environment_actions" ]]; then
  printf '%s\n' "$environment_actions" | sed 's/^/   /'
else
  echo "   - unknown; rerun scripts/internal/manual_smoke_environment_preflight.sh"
fi
echo "5. Before recording PASS, confirm executable devices with scripts/internal/manual_smoke_environment_preflight.sh."
echo "6. When a physical iPhone or iPad is available, install the iOS candidate with scripts/internal/install_ios_release_candidate.sh before running device smoke."
echo "7. Use scripts/manual_smoke_session_guide.sh to print the preflight, install command, checklist pointer, and environment-scoped record-command templates in one place."
echo "8. Do not call the release complete until scripts/check_release_completion.sh passes."
echo
echo "Current readiness:"
printf '%s\n' "$readiness"
