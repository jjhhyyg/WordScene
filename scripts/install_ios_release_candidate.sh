#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/tmp/WordSceneReleaseCandidates/iOS/Build/Products/Release-iphoneos/Word Scene.app"
DEVICE=""
DEVICE_LIST_FILE=""
DRY_RUN=0
TIMEOUT=120

usage() {
  echo "Usage: $0 [--app <Word Scene.app>] [--device <identifier>] [--device-list <path>] [--timeout <seconds>] [--dry-run]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      APP_PATH="$2"
      shift 2
      ;;
    --device)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DEVICE="$2"
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
    --timeout)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "iOS release candidate app not found: $APP_PATH" >&2
  echo "Run scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all first." >&2
  exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -le 0 ]]; then
  echo "Timeout must be a positive integer, got: $TIMEOUT" >&2
  exit 64
fi

device_list() {
  if [[ -n "$DEVICE_LIST_FILE" ]]; then
    cat "$DEVICE_LIST_FILE"
    return
  fi

  xcrun devicectl list devices
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

device_state_for_identifier() {
  local requested_device="$1"

  device_list |
    awk -v requested_device="$requested_device" '
      NR > 2 && index($0, requested_device) > 0 {
        if ($0 ~ /[[:space:]]available[[:space:]]/) {
          print "available"
          exit
        }
        if ($0 ~ /[[:space:]]unavailable[[:space:]]/) {
          print "unavailable"
          exit
        }
        print "unknown"
        exit
      }
    '
}

if [[ -z "$DEVICE" ]]; then
  if ! command -v xcrun >/dev/null 2>&1 && [[ -z "$DEVICE_LIST_FILE" ]]; then
    echo "xcrun is required to find an available iPhone or iPad." >&2
    exit 1
  fi

  DEVICE="$(first_available_mobile_device)"
fi

if [[ -z "$DEVICE" ]]; then
  echo "No available physical iPhone or iPad was reported by devicectl." >&2
  echo "Connect and unlock a target device, then rerun scripts/manual_smoke_environment_preflight.sh." >&2
  exit 1
fi

device_state="$(device_state_for_identifier "$DEVICE")"
if [[ "$device_state" == "unavailable" ]]; then
  echo "Selected iPhone/iPad is visible but unavailable: $DEVICE" >&2
  echo "Unlock it, trust this Mac, confirm Developer Mode, and reconnect or re-pair it before installing." >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'DRY RUN: xcrun devicectl device install app --device %q %q --timeout %q\n' "$DEVICE" "$APP_PATH" "$TIMEOUT"
  exit 0
fi

xcrun devicectl device install app --device "$DEVICE" "$APP_PATH" --timeout "$TIMEOUT"
