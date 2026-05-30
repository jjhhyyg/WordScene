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

print_environment_state() {
  local label="$1"
  local ready="$2"
  local detail="$3"

  if [[ "$ready" -eq 1 ]]; then
    printf -- '- %s: READY - %s\n' "$label" "$detail"
  else
    printf -- '- %s: WAIT - %s\n' "$label" "$detail"
  fi
}

print_device_guidance() {
  if [[ "$has_available_mobile" -eq 1 ]]; then
    echo "- Physical iPhone/iPad detected as available or connected; install the iOS candidate before recording device smoke."
  elif [[ -n "$unavailable_mobile" ]]; then
    echo "- A physical iPhone/iPad is visible but unavailable; unlock it, trust this Mac, confirm Developer Mode, and reconnect or re-pair it before smoke."
  else
    echo "- No physical iPhone/iPad is visible; connect or pair a real device. Simulator runs do not satisfy release smoke evidence."
  fi

  if [[ "$has_ios_candidate" -eq 0 ]]; then
    echo "- iOS candidate app is missing; rerun scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all after release-critical changes."
  fi

  if [[ "$has_macos_candidate" -eq 0 ]]; then
    echo "- Signed macOS candidate app is missing; restore the Xcode account/profile for team JU68L3U235 before macOS and iCloud smoke."
  fi
}

readiness="$("$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --summary)"
ready_count="$(printf '%s\n' "$readiness" | sed -n 's/^Ready rows: //p' | tail -n 1)"
waiting_count="$(printf '%s\n' "$readiness" | sed -n 's/^Waiting rows: //p' | tail -n 1)"

devices="$(device_list)"
available_mobile="$(
  printf '%s\n' "$devices" |
    awk 'NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]](available|connected)[[:space:]]/ { print }'
)"
unavailable_mobile="$(
  printf '%s\n' "$devices" |
    awk 'NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]]unavailable[[:space:]]/ { print }'
)"
ios_candidate_app="$CANDIDATE_ROOT/iOS/Build/Products/Release-iphoneos/Word Scene.app"
macos_candidate_app="$CANDIDATE_ROOT/macOS/Build/Products/Release/Word Scene.app"
has_available_mobile=0
has_ios_candidate=0
has_macos_candidate=0
has_unsigned_macos=0

[[ -n "$available_mobile" ]] && has_available_mobile=1
[[ -d "$ios_candidate_app" ]] && has_ios_candidate=1
[[ -d "$macos_candidate_app" ]] && has_macos_candidate=1
[[ -d "$UNSIGNED_MACOS_RELEASE_APP" ]] && has_unsigned_macos=1

ios_device_ready=0
macos_ready=0
cross_platform_ready=0
local_only_ready=0

if [[ "$has_available_mobile" -eq 1 && "$has_ios_candidate" -eq 1 ]]; then
  ios_device_ready=1
fi

if [[ "$has_macos_candidate" -eq 1 ]]; then
  macos_ready=1
fi

if [[ "$has_available_mobile" -eq 1 && "$has_ios_candidate" -eq 1 && "$has_macos_candidate" -eq 1 ]]; then
  cross_platform_ready=1
fi

if [[ "$has_available_mobile" -eq 1 && "$has_ios_candidate" -eq 1 && "$has_unsigned_macos" -eq 1 ]]; then
  local_only_ready=1
fi

echo "Manual Smoke Environment Preflight"
echo
echo "Evidence readiness:"
printf -- '- Ready rows: %s\n' "${ready_count:-unknown}"
printf -- '- Waiting rows: %s\n' "${waiting_count:-unknown}"
echo
echo "Candidate artifacts:"
print_artifact_state "iOS release candidate app" "$ios_candidate_app"
print_artifact_state "macOS release candidate app" "$macos_candidate_app"
print_artifact_state "unsigned macOS Release app for local-only fallback" "$UNSIGNED_MACOS_RELEASE_APP"
echo
echo "Physical iPhone/iPad devices reported by devicectl:"
echo "Available:"
print_device_rows "available" "$available_mobile"
echo "Unavailable:"
print_device_rows "unavailable" "$unavailable_mobile"
echo
echo "Executable smoke environments:"
print_environment_state "iOS/iPadOS device smoke" "$ios_device_ready" "requires an available physical iPhone/iPad and the iOS candidate app"
print_environment_state "macOS signed-candidate smoke" "$macos_ready" "requires the signed macOS candidate app"
print_environment_state "Cross-platform iCloud smoke" "$cross_platform_ready" "requires an available physical iPhone/iPad plus signed iOS and macOS candidates"
print_environment_state "Local-only fallback smoke" "$local_only_ready" "requires an available physical iPhone/iPad, the iOS candidate app, and the unsigned macOS Release app"
echo
echo "Execution guidance:"
echo "- READY means release evidence allows recording that row; it is not proof the smoke was run."
echo "- Do not record PASS for iPhone/iPad rows until the target physical device has actually run the checklist."
echo "- Do not record macOS or iCloud PASS rows until a signed macOS candidate exists."
echo "- Do not record the local-only fallback row until both the iOS candidate is installed on a physical device and the unsigned macOS Release app has actually run the checklist."
echo
echo "Next environment actions:"
print_device_guidance
