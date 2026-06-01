#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="all"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
ALLOW_PROVISIONING_UPDATES=0
export DERIVED_DATA_BASE="${DERIVED_DATA_BASE:-/tmp/WordSceneReleaseCandidates}"

BUILD_CANDIDATES_SCRIPT="${WORDSCENE_BUILD_CANDIDATES_SCRIPT:-$ROOT/scripts/internal/build_release_candidates.sh}"
COLLECT_EVIDENCE_SCRIPT="${WORDSCENE_COLLECT_EVIDENCE_SCRIPT:-$ROOT/scripts/internal/collect_release_candidate_evidence.sh}"
DIAGNOSE_SIGNING_SCRIPT="${WORDSCENE_DIAGNOSE_SIGNING_SCRIPT:-$ROOT/scripts/internal/diagnose_release_signing.sh}"
VERIFY_READINESS_SCRIPT="${WORDSCENE_VERIFY_RELEASE_READINESS_SCRIPT:-$ROOT/scripts/internal/verify_release_readiness.sh}"

usage() {
  echo "Usage: $0 [--allow-provisioning-updates] [--platform all|macos|ios] [--evidence <markdown>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-provisioning-updates)
      ALLOW_PROVISIONING_UPDATES=1
      shift
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PLATFORM="$2"
      shift 2
      ;;
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

case "$PLATFORM" in
  all|macos|ios) ;;
  *)
    echo "Unsupported platform '$PLATFORM'. Expected all, macos, or ios." >&2
    exit 64
    ;;
esac

assert_clean_worktree() {
  if [[ "${WORDSCENE_SKIP_DIRTY_RELEASE_GATE_CHECK:-0}" == "1" ]]; then
    return
  fi

  local dirty
  dirty="$(git -C "$ROOT" status --porcelain)"
  if [[ -n "$dirty" ]]; then
    cat >&2 <<ERROR
Release candidate gate requires a clean git worktree.
Commit or stash local changes before generating release candidate evidence.

$dirty
ERROR
    exit 1
  fi
}

assert_clean_worktree

platforms=()
case "$PLATFORM" in
  all)
    platforms=(macos ios)
    ;;
  macos|ios)
    platforms=("$PLATFORM")
    ;;
esac

mkdir -p "$(dirname "$EVIDENCE_FILE")" "$DERIVED_DATA_BASE/logs"

prepare_evidence_file() {
  local temp_file
  local preserved_rows
  local preserved_rest

  temp_file="$(mktemp)"
  preserved_rows="$(mktemp)"
  preserved_rest="$(mktemp)"

  if [[ -f "$EVIDENCE_FILE" ]]; then
    awk -F'|' -v platform="$PLATFORM" '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      function normalized_platform(value) {
        value = trim(value)
        gsub(/iOS/, "ios", value)
        gsub(/macOS/, "macos", value)
        return value
      }
      /^## Non-Manual Release Gate$/ {
        in_section = 1
        next
      }
      in_section == 1 && /^## / {
        in_section = 0
      }
      in_section == 1 &&
      /^\| / &&
      $0 !~ /^\| Area \|/ &&
      $0 !~ /^\| ---/ &&
      trim($2) != "Readiness script" {
        if (trim($2) == "Candidate gate") {
          if (platform == "all" || normalized_platform($3) == platform) {
            next
          }
        }
        print
      }
    ' "$EVIDENCE_FILE" >"$preserved_rows"

    awk -F'|' -v platform="$PLATFORM" -v requested_csv="$(requested_platforms_csv)" '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      function normalized_platform(value) {
        value = trim(value)
        gsub(/iOS/, "ios", value)
        gsub(/macOS/, "macos", value)
        return value
      }
      function is_requested(value) {
        return requested[normalized_platform(value)] == 1
      }
      function starts_build_section(value) {
        return value == "## Release Candidate Build Evidence" ||
          value == "## Release Candidate Build Blocker" ||
          value == "## Current Build Blockers"
      }
      function flush_build_section() {
        if (in_build_section == 1 && platform != "all" && build_section_has_requested != 1) {
          printf "%s", build_section
        }
        in_build_section = 0
        build_section = ""
        build_section_has_requested = 0
      }
      BEGIN {
        split(requested_csv, requested_values, ",")
        for (requested_index in requested_values) {
          requested[requested_values[requested_index]] = 1
        }
      }
      /^## Non-Manual Release Gate$/ ||
      /^## Release Candidate Build Evidence$/ ||
      /^## Release Candidate Build Blocker$/ ||
      /^## Current Build Blockers$/ {
        flush_build_section()
      }
      /^## Non-Manual Release Gate$/ {
        skip = 1
        next
      }
      starts_build_section($0) {
        in_build_section = 1
        build_section = $0 ORS
        next
      }
      /^## / {
        flush_build_section()
        skip = 0
      }
      in_build_section == 1 {
        build_section = build_section $0 ORS
        if ($0 ~ /^\| / && trim($2) == "Candidate build" && is_requested($3)) {
          build_section_has_requested = 1
        }
        next
      }
      skip != 1 {
        print
      }
      END {
        flush_build_section()
      }
    ' "$EVIDENCE_FILE" >"$preserved_rest"
  fi

  {
    printf '## Non-Manual Release Gate\n\n'
    printf '| Area | Platform | Device / OS | Build | Result | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    cat "$preserved_rows"
    if [[ -s "$preserved_rest" ]]; then
      printf '\n'
      cat "$preserved_rest"
    fi
  } >"$temp_file"

  mv "$temp_file" "$EVIDENCE_FILE"
  rm -f "$preserved_rows" "$preserved_rest"
}

append_non_manual_gate_row() {
  local area="$1"
  local platform="$2"
  local result="$3"
  local notes="$4"
  local row
  local temp_file
  local preserved_rows
  local preserved_rest

  row="| $area | $platform | local build host | 1 | $result | $notes |"
  temp_file="$(mktemp)"
  preserved_rows="$(mktemp)"
  preserved_rest="$(mktemp)"

  if [[ -f "$EVIDENCE_FILE" ]]; then
    awk '
      /^## Non-Manual Release Gate$/ {
        in_section = 1
        next
      }
      in_section == 1 && /^## / {
        in_section = 0
      }
      in_section == 1 &&
      /^\| / &&
      $0 !~ /^\| Area \|/ &&
      $0 !~ /^\| ---/ {
        print
      }
    ' "$EVIDENCE_FILE" >"$preserved_rows"

    awk '
      /^## Non-Manual Release Gate$/ {
        skip = 1
        next
      }
      /^## / {
        skip = 0
      }
      skip != 1 {
        print
      }
    ' "$EVIDENCE_FILE" >"$preserved_rest"
  fi

  {
    printf '## Non-Manual Release Gate\n\n'
    printf '| Area | Platform | Device / OS | Build | Result | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    cat "$preserved_rows"
    printf '%s\n' "$row"
    if [[ -s "$preserved_rest" ]]; then
      printf '\n'
      cat "$preserved_rest"
    fi
  } >"$temp_file"

  mv "$temp_file" "$EVIDENCE_FILE"
  rm -f "$preserved_rows" "$preserved_rest"
}

run_readiness() {
  local log_file="$DERIVED_DATA_BASE/logs/release-readiness.log"
  local notes

  printf '\n==> Running release readiness checks\n'
  local status=0
  if "$VERIFY_READINESS_SCRIPT" >"$log_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    cat "$log_file" >&2
    notes="scripts/internal/verify_release_readiness.sh failed before release candidate builds; see $log_file"
    prepare_evidence_file
    append_non_manual_gate_row "Readiness script" "macOS + iOS generic" "BLOCKED" "$notes"
    return "$status"
  fi

  notes="scripts/internal/verify_release_readiness.sh passed script syntax checks, shell regression tests, git diff --check, token leak scan, privacy manifest validation, required-reason API scan, privacy surface validation, CloudKit background-mode validation, XcodeGen version-marker scan, macOS tests, iOS simulator tests, iOS generic build, and unsigned macOS/iOS Release compiles."
  prepare_evidence_file
  append_non_manual_gate_row "Readiness script" "macOS + iOS generic" "PASS" "$notes"
}

platform_label() {
  case "$1" in
    ios) printf 'iOS' ;;
    macos) printf 'macOS' ;;
  esac
}

gate_platform_label() {
  case "$PLATFORM" in
    all) printf 'macOS + iOS' ;;
    ios) printf 'iOS' ;;
    macos) printf 'macOS' ;;
  esac
}

requested_platforms_csv() {
  case "$PLATFORM" in
    all) printf 'ios,macos' ;;
    ios) printf 'ios' ;;
    macos) printf 'macos' ;;
  esac
}

app_path_for_platform() {
  case "$1" in
    ios)
      printf '%s\n' "$DERIVED_DATA_BASE/iOS/Build/Products/Release-iphoneos/Word Scene.app"
      ;;
    macos)
      printf '%s\n' "$DERIVED_DATA_BASE/macOS/Build/Products/Release/Word Scene.app"
      ;;
  esac
}

append_blocker() {
  local platform="$1"
  local log_file="$2"
  local label
  local notes

  label="$(platform_label "$platform")"
  if [[ -x "$DIAGNOSE_SIGNING_SCRIPT" ]]; then
    notes="$("$DIAGNOSE_SIGNING_SCRIPT" --platform "$platform" --log "$log_file" | tr '\n' ' ' | sed 's/|/\//g; s/[[:space:]][[:space:]]*/ /g')"
  else
    notes=""
  fi
  if [[ -z "$notes" ]]; then
    notes="$(tail -n 8 "$log_file" | tr '\n' ' ' | sed 's/|/\//g; s/[[:space:]][[:space:]]*/ /g')"
  fi
  if [[ -z "$notes" ]]; then
    notes="Release candidate build failed; see $log_file"
  else
    notes="$notes See $log_file"
  fi

  {
    if [[ -s "$EVIDENCE_FILE" ]]; then
      printf '\n'
    fi
    printf '## Release Candidate Build Blocker\n\n'
    printf '| Area | Platform | Device / OS | Build | Result | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    printf '| Candidate build | %s | local build host | 1 | BLOCKED | %s |\n' "$label" "$notes"
  } >>"$EVIDENCE_FILE"
}

build_platform() {
  local platform="$1"
  local log_file="$DERIVED_DATA_BASE/logs/$platform-release-candidate.log"
  local build_args=(--platform "$platform")
  local app_path

  if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
    build_args=(--allow-provisioning-updates "${build_args[@]}")
  fi

  printf '\n==> Building %s release candidate\n' "$(platform_label "$platform")"
  local status=0
  if "$BUILD_CANDIDATES_SCRIPT" "${build_args[@]}" >"$log_file" 2>&1; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    cat "$log_file" >&2
    append_blocker "$platform" "$log_file"
    return "$status"
  fi

  app_path="$(app_path_for_platform "$platform")"
  printf '==> Recording %s release candidate evidence\n' "$(platform_label "$platform")"
  "$COLLECT_EVIDENCE_SCRIPT" \
    --platform "$platform" \
    --app "$app_path" \
    --output "$EVIDENCE_FILE"
}

run_readiness

overall_status=0
for platform in "${platforms[@]}"; do
  set +e
  build_platform "$platform"
  platform_status=$?
  set -e

  if [[ "$platform_status" -ne 0 && "$overall_status" -eq 0 ]]; then
    overall_status=$platform_status
  fi
done

if [[ "$overall_status" -ne 0 ]]; then
  append_non_manual_gate_row \
    "Candidate gate" \
    "$(gate_platform_label)" \
    "BLOCKED" \
    "scripts/run_release_candidate_gate.sh recorded release readiness, candidate build evidence, and signing blockers; rerun after resolving the blocked platform."
  exit "$overall_status"
fi

append_non_manual_gate_row \
  "Candidate gate" \
  "$(gate_platform_label)" \
  "PASS" \
  "scripts/run_release_candidate_gate.sh recorded release readiness and signed release candidate evidence for all requested platforms."

printf '\nRelease candidate gate completed. Evidence: %s\n' "$EVIDENCE_FILE"
