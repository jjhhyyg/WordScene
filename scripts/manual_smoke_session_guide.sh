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

first_available_mobile_device() {
  device_list |
    awk '
      NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]](available|connected)[[:space:]]/ {
        for (field = 1; field <= NF; field++) {
          if ($field ~ /^[0-9A-Fa-f-]{36}$/) {
            print $field
            exit
          }
        }
      }
    '
}

readiness_summary="$("$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --summary)"
ios_candidate_app="$CANDIDATE_ROOT/iOS/Build/Products/Release-iphoneos/Word Scene.app"
macos_candidate_app="$CANDIDATE_ROOT/macOS/Build/Products/Release/Word Scene.app"
device="$(first_available_mobile_device)"
can_install_ios=0
can_run_macos=0
can_run_local_only=0
preflight_args=(
  --evidence "$EVIDENCE_FILE"
  --candidate-root "$CANDIDATE_ROOT"
  --unsigned-macos-app "$UNSIGNED_MACOS_RELEASE_APP"
)

if [[ -n "$DEVICE_LIST_FILE" ]]; then
  preflight_args+=(--device-list "$DEVICE_LIST_FILE")
fi

echo "Manual Smoke Session Guide"
echo
echo "1. Environment preflight:"
"$ROOT/scripts/manual_smoke_environment_preflight.sh" "${preflight_args[@]}"

echo
echo "2. Install current iOS candidate:"
if [[ -d "$ios_candidate_app" && -n "$device" ]]; then
  can_install_ios=1
  printf 'scripts/install_ios_release_candidate.sh --device %q --app %q\n' "$device" "$ios_candidate_app"
else
  echo "WAIT: An available physical iPhone/iPad and iOS candidate app are required before install."
fi

echo
echo "3. Run the relevant checklist sections in docs/release-smoke-test.md."

if [[ -d "$macos_candidate_app" ]]; then
  can_run_macos=1
fi

if [[ "$can_install_ios" -eq 1 && -d "$UNSIGNED_MACOS_RELEASE_APP" ]]; then
  can_run_local_only=1
fi

if [[ "$can_install_ios" -eq 1 || "$can_run_macos" -eq 1 || "$can_run_local_only" -eq 1 ]]; then
  echo "4. Record only smoke rows that were actually executed and passed:"

  if [[ "$can_install_ios" -eq 1 ]]; then
    echo
    echo "iOS/iPadOS device rows:"
    "$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --commands --summary --scope ios-device
  fi

  if [[ "$can_run_macos" -eq 1 ]]; then
    echo
    echo "macOS signed-candidate rows:"
    "$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --commands --summary --scope macos
  fi

  if [[ "$can_install_ios" -eq 1 && "$can_run_macos" -eq 1 ]]; then
    echo
    echo "Cross-platform signed-candidate rows:"
    "$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --commands --summary --scope cross-platform
  fi

  if [[ "$can_run_local_only" -eq 1 ]]; then
    echo
    echo "Local-only fallback row:"
    "$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --commands --summary --scope local-only
  elif [[ "$can_install_ios" -eq 1 ]]; then
    echo
    printf 'Local-only fallback command is hidden until the unsigned macOS Release app is available: %s\n' "$UNSIGNED_MACOS_RELEASE_APP"
  fi
else
  echo "4. PASS record commands are hidden until an executable candidate environment is available."
  printf '%s\n' "$readiness_summary"
fi
