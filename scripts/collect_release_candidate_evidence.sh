#!/usr/bin/env bash
set -euo pipefail

PLATFORM=""
APP=""
ENTITLEMENTS=""
OUTPUT_FILE=""

usage() {
  echo "Usage: $0 --platform ios|macos --app <App.app> [--entitlements <plist>] [--output <markdown>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PLATFORM="$2"
      shift 2
      ;;
    --app)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      APP="$2"
      shift 2
      ;;
    --entitlements)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      ENTITLEMENTS="$2"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

case "$PLATFORM" in
  ios|macos) ;;
  *)
    usage
    exit 64
    ;;
esac

if [[ ! -d "$APP" ]]; then
  echo "App bundle not found: $APP" >&2
  exit 66
fi

INFO_PLIST="$APP/Info.plist"
if [[ "$PLATFORM" == "macos" ]]; then
  INFO_PLIST="$APP/Contents/Info.plist"
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Info.plist not found: $INFO_PLIST" >&2
  exit 66
fi

plist_value() {
  local plist="$1"
  local key="$2"
  local fallback="$3"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || printf '%s\n' "$fallback"
}

plist_array_csv() {
  local plist="$1"
  local key="$2"
  local fallback="$3"
  local values
  values="$(
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null |
      awk '
        /^[[:space:]]+[^{}]/ {
          gsub(/^[ \t]+|[ \t]+$/, "")
          if ($0 != "") {
            values[++count] = $0
          }
        }
        END {
          for (i = 1; i <= count; i++) {
            printf "%s%s", values[i], (i < count ? ", " : "")
          }
        }
      '
  )"
  if [[ -z "$values" ]]; then
    printf '%s\n' "$fallback"
  else
    printf '%s\n' "$values"
  fi
}

TEMP_ENTITLEMENTS=""
cleanup() {
  if [[ -n "$TEMP_ENTITLEMENTS" ]]; then
    rm -f "$TEMP_ENTITLEMENTS"
  fi
}
trap cleanup EXIT

if [[ -z "$ENTITLEMENTS" ]]; then
  TEMP_ENTITLEMENTS="$(mktemp)"
  if codesign -d --entitlements :- "$APP" >"$TEMP_ENTITLEMENTS" 2>/dev/null; then
    ENTITLEMENTS="$TEMP_ENTITLEMENTS"
  else
    ENTITLEMENTS=""
  fi
fi

entitlement_array_csv() {
  local key="$1"
  if [[ -z "$ENTITLEMENTS" || ! -f "$ENTITLEMENTS" ]]; then
    printf 'unavailable\n'
    return
  fi
  plist_array_csv "$ENTITLEMENTS" "$key" "missing"
}

BUNDLE_ID="$(plist_value "$INFO_PLIST" CFBundleIdentifier missing)"
VERSION="$(plist_value "$INFO_PLIST" CFBundleShortVersionString missing)"
BUILD="$(plist_value "$INFO_PLIST" CFBundleVersion missing)"
IPAD_ORIENTATIONS="$(plist_array_csv "$INFO_PLIST" 'UISupportedInterfaceOrientations~ipad' 'missing')"
CLOUDKIT_CONTAINERS="$(entitlement_array_csv 'com.apple.developer.icloud-container-identifiers')"
ICLOUD_SERVICES="$(entitlement_array_csv 'com.apple.developer.icloud-services')"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
PLATFORM_LABEL="$([[ "$PLATFORM" == "ios" ]] && printf 'iOS' || printf 'macOS')"

EVIDENCE="$(
  cat <<EOF
## Release Candidate Build Evidence

Generated: $TIMESTAMP

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | $PLATFORM_LABEL | local build host | $BUILD | PASS | $APP |

| Field | Value |
| --- | --- |
| Bundle ID | $BUNDLE_ID |
| Version | $VERSION |
| Build | $BUILD |
| iPad orientations | $IPAD_ORIENTATIONS |
| CloudKit containers | $CLOUDKIT_CONTAINERS |
| iCloud services | $ICLOUD_SERVICES |
EOF
)"

if [[ -n "$OUTPUT_FILE" ]]; then
  {
    if [[ -s "$OUTPUT_FILE" ]]; then
      printf '\n'
    fi
    printf '%s\n' "$EVIDENCE"
  } >>"$OUTPUT_FILE"
else
  printf '%s\n' "$EVIDENCE"
fi
