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

has_pass_row() {
  local area="$1"
  local platform="$2"

  awk -F'|' -v expected_area="$area" -v expected_platform="$platform" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == expected_area &&
    trim($3) == expected_platform &&
    trim($6) == "PASS" {
      found = 1
    }
    END {
      exit(found == 1 ? 0 : 1)
    }
  ' "$EVIDENCE_FILE"
}

has_candidate_git_commit() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "Git commit" {
      value = trim($3)
      if (value != "" && value != "unknown") {
        found = 1
      }
    }
    END {
      exit(found == 1 ? 0 : 1)
    }
  ' "$EVIDENCE_FILE"
}

required_rows() {
  cat <<'ROWS'
Readiness script|macOS + iOS generic
Candidate gate|macOS + iOS
DeepSeek live protocol smoke|API
Candidate build|macOS
Candidate build|iOS
Translation loop|macOS
Translation loop|iPhone
Translation loop|iPad
Import/export|macOS
Import/export|iOS/iPadOS
Local recovery|macOS
Local recovery|iOS/iPadOS
iCloud create sync|iPhone + macOS
iCloud delete sync|iPhone + macOS
Local-only fallback|macOS/iOS
ROWS
}

status=0

while IFS='|' read -r area platform; do
  if ! has_pass_row "$area" "$platform"; then
    echo "Missing PASS evidence: $area / $platform" >&2
    status=1
  fi
done < <(required_rows)

blocking_rows="$(
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($6) == "BLOCKED" || trim($6) == "FAIL" {
      printf "%s / %s / %s\n", trim($2), trim($3), trim($6)
    }
  ' "$EVIDENCE_FILE"
)"

if [[ -n "$blocking_rows" ]]; then
  while IFS= read -r row; do
    echo "Blocking evidence still present: $row" >&2
  done <<<"$blocking_rows"
  status=1
fi

if ! has_candidate_git_commit; then
  echo "Missing candidate build Git commit metadata." >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Release completion evidence is complete."
