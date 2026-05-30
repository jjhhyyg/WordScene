#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"

usage() {
  echo "Usage: $0 [--evidence <markdown>]" >&2
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

readiness="$("$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --summary)"
ready_rows="$(
  printf '%s\n' "$readiness" |
    awk '/^READY / {
      sub(/^READY /, "")
      print
    }'
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

echo "3. Before recording PASS, confirm executable devices with scripts/manual_smoke_environment_preflight.sh."
echo "4. When a physical iPhone or iPad is available, install the iOS candidate with scripts/install_ios_release_candidate.sh before running device smoke."
echo "5. Use scripts/manual_smoke_session_guide.sh to print the preflight, install command, checklist pointer, and record-command templates in one place."
echo "6. Do not call the release complete until scripts/check_release_completion.sh passes."
echo
echo "Current readiness:"
printf '%s\n' "$readiness"
