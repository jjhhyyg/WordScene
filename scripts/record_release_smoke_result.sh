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

ensure_section

printf '| %s | %s | %s | %s | %s | %s |\n' \
  "$(sanitize_cell "$AREA")" \
  "$(sanitize_cell "$PLATFORM")" \
  "$(sanitize_cell "$DEVICE")" \
  "$(sanitize_cell "$BUILD")" \
  "$(sanitize_cell "$RESULT")" \
  "$(sanitize_cell "$NOTES")" >>"$EVIDENCE_FILE"
