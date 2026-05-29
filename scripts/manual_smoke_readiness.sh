#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
SHOW_COMMANDS=0
SHOW_SUMMARY=0
CURRENT_COMMIT="${WORDSCENE_CURRENT_COMMIT:-$(git -C "$ROOT" rev-parse --short=12 HEAD)}"

usage() {
  echo "Usage: $0 [--evidence <markdown>] [--commands] [--summary]" >&2
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
    --commands)
      SHOW_COMMANDS=1
      shift
      ;;
    --summary)
      SHOW_SUMMARY=1
      shift
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

live_smoke_git_commit() {
  awk -F'|' '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    trim($2) == "DeepSeek live protocol smoke" &&
    trim($3) == "API" &&
    trim($6) == "PASS" {
      print trim($7)
      exit
    }
  ' "$EVIDENCE_FILE" |
    sed -n 's/.*Git commit `\([^`][^`]*\)`.*/\1/p'
}

commit_matches_current_head() {
  local evidence_commit="$1"

  [[ "${evidence_commit:0:12}" == "${CURRENT_COMMIT:0:12}" ]]
}

candidate_is_ancestor_of_head() {
  local evidence_commit="$1"

  if [[ -n "${WORDSCENE_CANDIDATE_IS_ANCESTOR+x}" ]]; then
    [[ "$WORDSCENE_CANDIDATE_IS_ANCESTOR" == "1" ]]
    return
  fi

  git -C "$ROOT" merge-base --is-ancestor "$evidence_commit" HEAD
}

changed_files_since_candidate() {
  local evidence_commit="$1"

  if [[ -n "${WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE+x}" ]]; then
    printf '%s\n' "$WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE"
    return
  fi

  git -C "$ROOT" diff --name-only "$evidence_commit"..HEAD
}

live_smoke_is_ancestor_of_head() {
  local evidence_commit="$1"

  if [[ -n "${WORDSCENE_LIVE_SMOKE_IS_ANCESTOR+x}" ]]; then
    [[ "$WORDSCENE_LIVE_SMOKE_IS_ANCESTOR" == "1" ]]
    return
  fi

  git -C "$ROOT" merge-base --is-ancestor "$evidence_commit" HEAD
}

changed_files_since_live_smoke() {
  local evidence_commit="$1"

  if [[ -n "${WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE+x}" ]]; then
    printf '%s\n' "$WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE"
    return
  fi

  git -C "$ROOT" diff --name-only "$evidence_commit"..HEAD
}

is_allowed_post_candidate_file() {
  case "$1" in
    docs/release-smoke-evidence.md | \
    docs/implementation-plan.md)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

candidate_freshness_reason() {
  local evidence_commit
  local disallowed=()
  local file
  local joined

  evidence_commit="$(candidate_git_commit)"
  if [[ -z "$evidence_commit" ]]; then
    printf 'fresh release candidate evidence required: missing candidate Git commit metadata'
    return
  fi

  if commit_matches_current_head "$evidence_commit"; then
    return
  fi

  if ! candidate_is_ancestor_of_head "$evidence_commit"; then
    printf 'fresh release candidate evidence required: evidence %s is not an ancestor of current %s' "$evidence_commit" "$CURRENT_COMMIT"
    return
  fi

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi
    if ! is_allowed_post_candidate_file "$file"; then
      disallowed+=("$file")
    fi
  done < <(changed_files_since_candidate "$evidence_commit")

  if [[ "${#disallowed[@]}" -gt 0 ]]; then
    joined="$(IFS=', '; printf '%s' "${disallowed[*]}")"
    printf 'fresh release candidate evidence required: %s changed after candidate build' "$joined"
  fi
}

live_smoke_freshness_reason() {
  local evidence_commit
  local disallowed=()
  local file
  local joined

  evidence_commit="$(live_smoke_git_commit)"
  if [[ -z "$evidence_commit" ]]; then
    printf 'missing current DeepSeek live protocol smoke PASS'
    return
  fi

  if commit_matches_current_head "$evidence_commit"; then
    return
  fi

  if ! live_smoke_is_ancestor_of_head "$evidence_commit"; then
    printf 'fresh DeepSeek live protocol smoke required: evidence %s is not an ancestor of current %s' "$evidence_commit" "$CURRENT_COMMIT"
    return
  fi

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi
    if ! is_allowed_post_candidate_file "$file"; then
      disallowed+=("$file")
    fi
  done < <(changed_files_since_live_smoke "$evidence_commit")

  if [[ "${#disallowed[@]}" -gt 0 ]]; then
    joined="$(IFS=', '; printf '%s' "${disallowed[*]}")"
    printf 'fresh DeepSeek live protocol smoke required: %s changed after live smoke' "$joined"
  fi
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

suggested_device_for() {
  case "$1|$2" in
    "Translation loop|iPhone" | \
    "Local recovery|iOS/iPadOS")
      printf 'iPhone 17 Pro Max / iOS 26.0'
      ;;
    "Translation loop|iPad" | \
    "Import/export|iOS/iPadOS")
      printf 'iPad Pro 11-inch / iPadOS 26.0'
      ;;
    "Local-only fallback|macOS/iOS")
      printf 'Unsigned Mac Release + iPhone 17 Pro Max / iOS 26.0'
      ;;
    *)
      printf '<device / OS>'
      ;;
  esac
}

print_record_command() {
  local area="$1"
  local platform="$2"
  local device

  device="$(suggested_device_for "$area" "$platform")"
  cat <<COMMAND
scripts/record_release_smoke_result.sh \\
  --evidence docs/release-smoke-evidence.md \\
  --area "$area" \\
  --platform "$platform" \\
  --device "$device" \\
  --build "$build_number" \\
  --result "PASS" \\
  --notes "<manual smoke notes>"
COMMAND
}

build_number="$(candidate_build_number)"
candidate_freshness_blocker="$(candidate_freshness_reason)"
live_smoke_freshness_blocker="$(live_smoke_freshness_reason)"

echo "Manual Smoke Readiness"
if [[ -n "$build_number" ]]; then
  echo "Candidate build: $build_number"
else
  echo "Candidate build: missing"
fi

ready_count=0
waiting_count=0
waiting_reasons=""

while IFS='|' read -r area platform required_platforms; do
  reason=""
  missing_platforms="$(missing_platforms_for "$required_platforms")"

  if [[ -z "$build_number" ]]; then
    reason="missing candidate build number metadata"
  elif [[ -n "$candidate_freshness_blocker" ]]; then
    reason="$candidate_freshness_blocker"
  elif [[ -n "$live_smoke_freshness_blocker" ]]; then
    reason="$live_smoke_freshness_blocker"
  elif [[ -n "$missing_platforms" ]]; then
    reason="missing PASS candidate build: $missing_platforms"
  fi

  if [[ -z "$reason" ]]; then
    ready_count=$((ready_count + 1))
    echo "READY $area / $platform"
    if [[ "$SHOW_COMMANDS" -eq 1 ]]; then
      print_record_command "$area" "$platform"
    fi
  else
    waiting_count=$((waiting_count + 1))
    waiting_reasons="${waiting_reasons}${reason}"$'\n'
    echo "WAITING $area / $platform - $reason"
  fi
done < <(manual_rows)

if [[ "$SHOW_SUMMARY" -eq 1 ]]; then
  echo "Summary"
  echo "Ready rows: $ready_count"
  echo "Waiting rows: $waiting_count"
  if [[ "$waiting_count" -gt 0 ]]; then
    echo "Waiting reasons:"
    printf '%s' "$waiting_reasons" |
      sed '/^$/d' |
      sort |
      uniq -c |
      awk '{
        count = $1
        sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "")
        printf "- %s (%s rows)\n", $0, count
      }'
  fi
fi
