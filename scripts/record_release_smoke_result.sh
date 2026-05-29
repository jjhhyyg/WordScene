#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_COMMIT="${WORDSCENE_CURRENT_COMMIT:-$(git -C "$ROOT" rev-parse --short=12 HEAD)}"

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

candidate_matches_current_head() {
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

assert_current_candidate_commit() {
  local evidence_commit="$1"
  local disallowed=()
  local file
  local joined

  if candidate_matches_current_head "$evidence_commit"; then
    return
  fi

  if ! candidate_is_ancestor_of_head "$evidence_commit"; then
    echo "Manual smoke evidence requires current release candidate metadata: evidence $evidence_commit is not an ancestor of current $CURRENT_COMMIT." >&2
    exit 1
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
    echo "Manual smoke evidence requires fresh release candidate metadata; release-critical files changed since candidate build: $joined. Rerun scripts/run_release_candidate_gate.sh." >&2
    exit 1
  fi
}

assert_current_live_smoke_commit() {
  local evidence_commit="$1"
  local disallowed=()
  local file
  local joined

  if candidate_matches_current_head "$evidence_commit"; then
    return
  fi

  if ! live_smoke_is_ancestor_of_head "$evidence_commit"; then
    echo "Manual smoke evidence requires current DeepSeek live protocol smoke metadata: evidence $evidence_commit is not an ancestor of current $CURRENT_COMMIT." >&2
    exit 1
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
    echo "Manual smoke evidence requires fresh DeepSeek live protocol smoke metadata; release-critical files changed since live API smoke: $joined. Rerun scripts/run_live_deepseek_translation_smoke.sh." >&2
    exit 1
  fi
}

assert_current_live_smoke_metadata() {
  local evidence_commit

  evidence_commit="$(live_smoke_git_commit)"
  if [[ -z "$evidence_commit" ]]; then
    echo "Manual smoke evidence requires current DeepSeek live protocol smoke metadata. Run scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md first." >&2
    exit 1
  fi

  assert_current_live_smoke_commit "$evidence_commit"
}

assert_current_candidate_metadata() {
  local evidence_commit

  evidence_commit="$(candidate_git_commit)"
  if [[ -z "$evidence_commit" ]]; then
    echo "Manual smoke evidence requires current release candidate metadata. Run scripts/run_release_candidate_gate.sh first." >&2
    exit 1
  fi

  assert_current_candidate_commit "$evidence_commit"
}

assert_candidate_build_number() {
  local evidence_build

  evidence_build="$(candidate_build_number)"
  if [[ -z "$evidence_build" ]]; then
    echo "Manual smoke evidence requires candidate build number metadata. Run scripts/run_release_candidate_gate.sh first." >&2
    exit 1
  fi

  if [[ "$BUILD_CELL" != "$evidence_build" ]]; then
    echo "Manual smoke evidence requires build $evidence_build, got $BUILD_CELL." >&2
    exit 1
  fi
}

required_candidate_platforms() {
  case "$1|$2" in
    "Translation loop|macOS" | \
    "Import/export|macOS" | \
    "Local recovery|macOS")
      printf 'macOS\n'
      ;;
    "Translation loop|iPhone" | \
    "Translation loop|iPad" | \
    "Import/export|iOS/iPadOS" | \
    "Local recovery|iOS/iPadOS")
      printf 'iOS\n'
      ;;
    "iCloud create sync|iPhone + macOS" | \
    "iCloud delete sync|iPhone + macOS")
      printf 'macOS\n'
      printf 'iOS\n'
      ;;
    "Local-only fallback|macOS/iOS")
      printf 'iOS\n'
      ;;
  esac
}

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

assert_required_candidate_builds() {
  local missing=()
  local platform

  while IFS= read -r platform; do
    if [[ -n "$platform" ]] && ! has_pass_candidate_build "$platform"; then
      missing+=("$platform")
    fi
  done < <(required_candidate_platforms "$AREA_CELL" "$PLATFORM_CELL")

  if [[ "${#missing[@]}" -gt 0 ]]; then
    local joined
    joined="$(IFS=', '; printf '%s' "${missing[*]}")"
    echo "Manual smoke evidence requires PASS candidate build evidence for: $joined." >&2
    exit 1
  fi
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

assert_current_candidate_metadata
assert_current_live_smoke_metadata
assert_candidate_build_number
assert_required_candidate_builds

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
