#!/usr/bin/env bash
set -euo pipefail

PLATFORM=""
LOG_FILE=""
DERIVED_DATA_BASE="${DERIVED_DATA_BASE:-/tmp/WordSceneReleaseCandidates}"

usage() {
  echo "Usage: $0 --platform macos|ios [--log <xcodebuild-log>]" >&2
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
    --log)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      LOG_FILE="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

case "$PLATFORM" in
  macos|ios) ;;
  *)
    usage
    exit 64
    ;;
esac

if [[ -z "$LOG_FILE" ]]; then
  LOG_FILE="$DERIVED_DATA_BASE/logs/$PLATFORM-release-candidate.log"
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "xcodebuild log not found: $LOG_FILE" >&2
  exit 66
fi

platform_label() {
  case "$PLATFORM" in
    macos) printf 'macOS' ;;
    ios) printf 'iOS' ;;
  esac
}

notes=()
next_actions=()

if grep -qF 'No Accounts: Add a new account in Accounts settings.' "$LOG_FILE"; then
  notes+=("Xcode has no active Apple Developer account session")
  next_actions+=("Open Xcode Settings > Accounts and add or re-authenticate the Apple ID for team JU68L3U235")
fi

if grep -q "No profiles for 'com.erikssonhou.leximemory' were found" "$LOG_FILE"; then
  if [[ "$PLATFORM" == "macos" ]]; then
    notes+=("Mac App Development provisioning profile is missing for com.erikssonhou.leximemory")
  else
    notes+=("iOS provisioning profile is missing for com.erikssonhou.leximemory")
  fi
  next_actions+=("After account authentication, rerun scripts/build_release_candidates.sh --allow-provisioning-updates --platform $PLATFORM")
fi

if grep -qi 'cloudkit\|icloud' "$LOG_FILE" && grep -qi 'entitlement\|container' "$LOG_FILE"; then
  notes+=("CloudKit entitlement or container access may need confirmation")
  next_actions+=("Confirm the iCloud container iCloud.com.erikssonhou.leximemory is enabled for team JU68L3U235")
fi

if [[ "${#notes[@]}" -eq 0 ]]; then
  notes+=("No known signing pattern matched; inspect the xcodebuild log directly")
  next_actions+=("Open $LOG_FILE and classify the first signing or provisioning error")
fi

join_with_semicolon() {
  local item
  local first=1
  for item in "$@"; do
    if [[ "$first" -eq 1 ]]; then
      first=0
    else
      printf '; '
    fi
    printf '%s' "$item"
  done
}

printf 'Signing diagnosis | %s | BLOCKED | ' "$(platform_label)"
join_with_semicolon "${notes[@]}"
printf ' | Next: '
join_with_semicolon "${next_actions[@]}"
printf ' |\n'
