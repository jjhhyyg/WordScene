#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
CANDIDATE_ROOT="/tmp/WordSceneReleaseCandidates"
DEVICE_LIST_FILE=""

usage() {
  echo "Usage: $0 [--evidence <markdown>] [--candidate-root <path>] [--device-list <path>]" >&2
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
      NR > 2 && $0 ~ /(iPhone|iPad)/ && $0 ~ /[[:space:]]available[[:space:]]/ {
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
candidate_app="$CANDIDATE_ROOT/iOS/Build/Products/Release-iphoneos/Word Scene.app"
device="$(first_available_mobile_device)"
can_install=0
preflight_args=(
  --evidence "$EVIDENCE_FILE"
  --candidate-root "$CANDIDATE_ROOT"
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
if [[ -d "$candidate_app" && -n "$device" ]]; then
  can_install=1
  printf 'scripts/install_ios_release_candidate.sh --device %q --app %q\n' "$device" "$candidate_app"
else
  echo "WAIT: An available physical iPhone/iPad and iOS candidate app are required before install."
fi

echo
echo "3. Run the relevant checklist sections in docs/release-smoke-test.md."
if [[ "$can_install" -eq 1 ]]; then
  echo "4. Record only smoke rows that were actually executed and passed:"
  "$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE_FILE" --commands --summary
else
  echo "4. PASS record commands are hidden until an installable physical device is available."
  printf '%s\n' "$readiness_summary"
fi
