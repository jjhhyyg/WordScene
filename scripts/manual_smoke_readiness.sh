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

has_pass_candidate_build() {
  local platform="$1"

  awk -F'|' -v expected_platform="$platform" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "Candidate build" &&
    trim($3) == expected_platform &&
    trim($6) == "PASS" {
      found = 1
    }
    END {
      exit(found == 1 ? 0 : 1)
    }
  ' "$EVIDENCE_FILE"
}

has_live_smoke_pass() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "DeepSeek live protocol smoke" &&
    trim($3) == "API" &&
    trim($6) == "PASS" &&
    trim($7) ~ /Git commit `/ {
      found = 1
    }
    END {
      exit(found == 1 ? 0 : 1)
    }
  ' "$EVIDENCE_FILE"
}

candidate_build_number() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "Build" {
      print trim($3)
      exit
    }
  ' "$EVIDENCE_FILE"
}

manual_rows() {
  cat <<'ROWS'
Translation loop|macOS|macOS
Translation loop|iPhone|iOS
Translation loop|iPad|iOS
Import/export|macOS|macOS
Import/export|iOS/iPadOS|iOS
Local recovery|macOS|macOS
Local recovery|iOS/iPadOS|iOS
iCloud create sync|iPhone + macOS|macOS,iOS
iCloud delete sync|iPhone + macOS|macOS,iOS
Local-only fallback|macOS/iOS|iOS
ROWS
}

missing_platforms_for() {
  local required_csv="$1"
  local required
  local missing=()
  local joined

  IFS=',' read -ra required <<<"$required_csv"
  for platform in "${required[@]}"; do
    if [[ -n "$platform" ]] && ! has_pass_candidate_build "$platform"; then
      missing+=("$platform")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    joined="$(IFS=', '; printf '%s' "${missing[*]}")"
    printf '%s' "$joined"
  fi
}

build_number="$(candidate_build_number)"
live_smoke_ready=0
if has_live_smoke_pass; then
  live_smoke_ready=1
fi

echo "Manual Smoke Readiness"
if [[ -n "$build_number" ]]; then
  echo "Candidate build: $build_number"
else
  echo "Candidate build: missing"
fi

while IFS='|' read -r area platform required_platforms; do
  reason=""
  missing_platforms="$(missing_platforms_for "$required_platforms")"

  if [[ -z "$build_number" ]]; then
    reason="missing candidate build number metadata"
  elif [[ "$live_smoke_ready" -ne 1 ]]; then
    reason="missing current DeepSeek live protocol smoke PASS"
  elif [[ -n "$missing_platforms" ]]; then
    reason="missing PASS candidate build: $missing_platforms"
  fi

  if [[ -z "$reason" ]]; then
    echo "READY $area / $platform"
  else
    echo "WAITING $area / $platform - $reason"
  fi
done < <(manual_rows)
