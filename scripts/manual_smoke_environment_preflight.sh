#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

device_list() {
  if [[ -n "$DEVICE_LIST_FILE" ]]; then
    cat "$DEVICE_LIST_FILE"
    return
  fi

  if command -v xcrun >/dev/null 2>&1; then
    xcrun devicectl list devices 2>/dev/null || true
  fi
}

print_artifact_state() {
  local label="$1"
  local path="$2"

  if [[ -e "$path" ]]; then
    printf -- '- %s: FOUND %s\n' "$label" "$path"
  else
    printf -- '- %s: MISSING %s\n' "$label" "$path"
  fi
}

print_device_rows() {
  local state="$1"
  local rows="$2"

  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows" | sed "s/^/- /"
  else
    printf -- '- none\n'
  fi
}

readiness="$("$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --summary)"
ready_count="$(printf '%s\n' "$readiness" | sed -n 's/^Ready rows: //p' | tail -n 1)"
waiting_count="$(printf '%s\n' "$readiness" | sed -n 's/^Waiting rows: //p' | tail -n 1)"

devices="$(device_list)"
available_mobile="$(
  printf '%s\n' "$devices" |
    awk 'NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]]available[[:space:]]/ { print }'
)"
unavailable_mobile="$(
  printf '%s\n' "$devices" |
    awk 'NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]]unavailable[[:space:]]/ { print }'
)"

echo "Manual Smoke Environment Preflight"
echo
echo "Evidence readiness:"
printf -- '- Ready rows: %s\n' "${ready_count:-unknown}"
printf -- '- Waiting rows: %s\n' "${waiting_count:-unknown}"
echo
echo "Candidate artifacts:"
print_artifact_state "iOS release candidate app" "$CANDIDATE_ROOT/iOS/Build/Products/Release-iphoneos/Word Scene.app"
print_artifact_state "macOS release candidate app" "$CANDIDATE_ROOT/macOS/Build/Products/Release/Word Scene.app"
print_artifact_state "unsigned macOS Release app for local-only fallback" "$UNSIGNED_MACOS_RELEASE_APP"
echo
echo "Physical iPhone/iPad devices reported by devicectl:"
echo "Available:"
print_device_rows "available" "$available_mobile"
echo "Unavailable:"
print_device_rows "unavailable" "$unavailable_mobile"
echo
echo "Execution guidance:"
echo "- READY means release evidence allows recording that row; it is not proof the smoke was run."
echo "- Do not record PASS for iPhone/iPad rows until the target physical device has actually run the checklist."
echo "- Do not record macOS or iCloud PASS rows until a signed macOS candidate exists."
echo "- Do not record the local-only fallback row until both the iOS candidate is installed on a physical device and the unsigned macOS Release app has actually run the checklist."
