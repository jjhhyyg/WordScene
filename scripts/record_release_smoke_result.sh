#!/usr/bin/env bash
set -euo pipefail

EVIDENCE_FILE=""
AREA=""
PLATFORM=""
DEVICE=""
BUILD=""
RESULT=""
NOTES=""

usage() {
  echo "Usage: $0 --evidence <markdown> --area <name> --platform <name> --device <name> --build <number> --result PASS|FAIL|BLOCKED --notes <text>" >&2
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
    --area)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      AREA="$2"
      shift 2
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PLATFORM="$2"
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
    --build)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      BUILD="$2"
      shift 2
      ;;
    --result)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      RESULT="$2"
      shift 2
      ;;
    --notes)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      NOTES="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ -z "$EVIDENCE_FILE" || -z "$AREA" || -z "$PLATFORM" || -z "$DEVICE" || -z "$BUILD" || -z "$RESULT" || -z "$NOTES" ]]; then
  usage
  exit 64
fi

case "$RESULT" in
  PASS|FAIL|BLOCKED) ;;
  *)
    echo "Unsupported result '$RESULT'. Expected PASS, FAIL, or BLOCKED." >&2
    exit 64
    ;;
esac

mkdir -p "$(dirname "$EVIDENCE_FILE")"
touch "$EVIDENCE_FILE"

sanitize_cell() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\//g; s/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

is_supported_manual_pair() {
  case "$1|$2" in
    "Translation loop|macOS" | \
    "Translation loop|iPhone" | \
    "Translation loop|iPad" | \
    "Import/export|macOS" | \
    "Import/export|iOS/iPadOS" | \
    "Local recovery|macOS" | \
    "Local recovery|iOS/iPadOS" | \
    "iCloud create sync|iPhone + macOS" | \
    "iCloud delete sync|iPhone + macOS" | \
    "Local-only fallback|macOS/iOS")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_section() {
  if grep -qF '## Manual Smoke Evidence' "$EVIDENCE_FILE"; then
    return
  fi

  {
    if [[ -s "$EVIDENCE_FILE" ]]; then
      printf '\n'
    fi
    printf '## Manual Smoke Evidence\n\n'
    printf '| Area | Platform | Device / OS | Build | Result | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
  } >>"$EVIDENCE_FILE"
}

AREA_CELL="$(sanitize_cell "$AREA")"
PLATFORM_CELL="$(sanitize_cell "$PLATFORM")"
DEVICE_CELL="$(sanitize_cell "$DEVICE")"
BUILD_CELL="$(sanitize_cell "$BUILD")"
RESULT_CELL="$(sanitize_cell "$RESULT")"
NOTES_CELL="$(sanitize_cell "$NOTES")"

if ! is_supported_manual_pair "$AREA_CELL" "$PLATFORM_CELL"; then
  cat >&2 <<ERROR
Unsupported manual smoke area/platform: '$AREA_CELL' / '$PLATFORM_CELL'.
Use one of the canonical pairs from docs/release-smoke-test.md:
  Translation loop / macOS
  Translation loop / iPhone
  Translation loop / iPad
  Import/export / macOS
  Import/export / iOS/iPadOS
  Local recovery / macOS
  Local recovery / iOS/iPadOS
  iCloud create sync / iPhone + macOS
  iCloud delete sync / iPhone + macOS
  Local-only fallback / macOS/iOS
ERROR
  exit 64
fi

ensure_section

ROW="| $AREA_CELL | $PLATFORM_CELL | $DEVICE_CELL | $BUILD_CELL | $RESULT_CELL | $NOTES_CELL |"
TEMP_FILE="$(mktemp)"

awk -F'|' \
  -v expected_area="$AREA_CELL" \
  -v expected_platform="$PLATFORM_CELL" \
  -v replacement_row="$ROW" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function maybe_insert_replacement() {
      if (in_manual == 1 && inserted == 0) {
        print replacement_row
        inserted = 1
      }
    }
    /^## Manual Smoke Evidence$/ {
      in_manual = 1
      print
      next
    }
    /^## / && in_manual == 1 {
      maybe_insert_replacement()
      in_manual = 0
      print
      next
    }
    in_manual == 1 &&
    trim($2) == expected_area &&
    trim($3) == expected_platform {
      next
    }
    {
      print
    }
    END {
      maybe_insert_replacement()
    }
  ' "$EVIDENCE_FILE" >"$TEMP_FILE"

mv "$TEMP_FILE" "$EVIDENCE_FILE"
