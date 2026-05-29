#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"

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

section_exists() {
  local section="$1"

  grep -qFx "## $section" "$EVIDENCE_FILE"
}

has_standard_area_table() {
  local section="$1"

  awk -v expected_heading="## $section" '
    $0 == expected_heading {
      in_section = 1
      previous = ""
      next
    }
    in_section == 1 && /^## / {
      in_section = 0
    }
    in_section == 1 &&
    previous == "| Area | Platform | Device / OS | Build | Result | Notes |" &&
    $0 == "| --- | --- | --- | --- | --- | --- |" {
      found = 1
    }
    in_section == 1 {
      previous = $0
    }
    END {
      exit(found == 1 ? 0 : 1)
    }
  ' "$EVIDENCE_FILE"
}

pass_row_count() {
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
      count += 1
    }
    END {
      print count + 0
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

candidate_git_commit() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "Git commit" {
      print trim($3)
      exit
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

required_table_sections=(
  "Non-Manual Release Gate"
  "Release Candidate Build Evidence"
)

optional_table_sections=(
  "Release Candidate Build Blocker"
  "Manual Smoke Evidence"
)

for section in "${required_table_sections[@]}"; do
  if ! has_standard_area_table "$section"; then
    echo "Malformed evidence table: $section" >&2
    status=1
  fi
done

for section in "${optional_table_sections[@]}"; do
  if section_exists "$section" && ! has_standard_area_table "$section"; then
    echo "Malformed evidence table: $section" >&2
    status=1
  fi
done

while IFS='|' read -r area platform; do
  pass_count="$(pass_row_count "$area" "$platform")"
  if [[ "$pass_count" -eq 0 ]]; then
    echo "Missing PASS evidence: $area / $platform" >&2
    status=1
  elif [[ "$pass_count" -gt 1 ]]; then
    echo "Duplicate PASS evidence: $area / $platform ($pass_count rows)" >&2
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
else
  evidence_commit="$(candidate_git_commit)"
  if [[ "${evidence_commit:0:12}" != "$CURRENT_COMMIT" ]]; then
    echo "Candidate build Git commit does not match current HEAD: evidence $evidence_commit, current $CURRENT_COMMIT." >&2
    status=1
  fi
fi

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "Release completion evidence is complete."
