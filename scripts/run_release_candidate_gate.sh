#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="all"
EVIDENCE_FILE="$ROOT/docs/release-smoke-evidence.md"
ALLOW_PROVISIONING_UPDATES=0
export DERIVED_DATA_BASE="${DERIVED_DATA_BASE:-/tmp/WordSceneReleaseCandidates}"

BUILD_CANDIDATES_SCRIPT="${WORDSCENE_BUILD_CANDIDATES_SCRIPT:-$ROOT/scripts/build_release_candidates.sh}"
COLLECT_EVIDENCE_SCRIPT="${WORDSCENE_COLLECT_EVIDENCE_SCRIPT:-$ROOT/scripts/collect_release_candidate_evidence.sh}"
DIAGNOSE_SIGNING_SCRIPT="${WORDSCENE_DIAGNOSE_SIGNING_SCRIPT:-$ROOT/scripts/diagnose_release_signing.sh}"

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
  temp_file="$(mktemp)"

  if [[ -f "$EVIDENCE_FILE" ]]; then
    awk '
      /^## Release Candidate Build Evidence$/ ||
      /^## Release Candidate Build Blocker$/ ||
      /^## Current Build Blockers$/ {
        skip = 1
        next
      }
      /^## / {
        skip = 0
      }
      skip != 1 {
        print
      }
    ' "$EVIDENCE_FILE" >"$temp_file"
  fi

  mv "$temp_file" "$EVIDENCE_FILE"
}

prepare_evidence_file

platform_label() {
  case "$1" in
    ios) printf 'iOS' ;;
    macos) printf 'macOS' ;;
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
  exit "$overall_status"
fi

printf '\nRelease candidate gate completed. Evidence: %s\n' "$EVIDENCE_FILE"
