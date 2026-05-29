#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

LOG="$TMPDIR/macos-signing.log"

cat >"$LOG" <<'LOG_TEXT'
/Users/erikssonhou/Documents/WordScene/WordScene.xcodeproj: error: No Accounts: Add a new account in Accounts settings. (in target 'WordSceneMac' from project 'WordScene')
/Users/erikssonhou/Documents/WordScene/WordScene.xcodeproj: error: No profiles for 'com.erikssonhou.leximemory' were found: Xcode couldn't find any Mac App Development provisioning profiles matching 'com.erikssonhou.leximemory'. (in target 'WordSceneMac' from project 'WordScene')
** BUILD FAILED **
LOG_TEXT

OUTPUT="$("$ROOT/scripts/diagnose_release_signing.sh" --platform macos --log "$LOG")"

grep -qF 'Signing diagnosis | macOS | BLOCKED |' <<<"$OUTPUT"
grep -qF 'Xcode has no active Apple Developer account session' <<<"$OUTPUT"
grep -qF 'Mac App Development provisioning profile is missing for com.erikssonhou.leximemory' <<<"$OUTPUT"
grep -qF 'Open Xcode Settings > Accounts' <<<"$OUTPUT"

DEFAULT_BASE="$TMPDIR/default-candidates"
mkdir -p "$DEFAULT_BASE/logs"
cp "$LOG" "$DEFAULT_BASE/logs/macos-release-candidate.log"

DEFAULT_OUTPUT="$(DERIVED_DATA_BASE="$DEFAULT_BASE" "$ROOT/scripts/diagnose_release_signing.sh" --platform macos)"

grep -qF 'Signing diagnosis | macOS | BLOCKED |' <<<"$DEFAULT_OUTPUT"
grep -qF 'Xcode has no active Apple Developer account session' <<<"$DEFAULT_OUTPUT"
