#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

APP="$TMPDIR/Fake.app"
ENTITLEMENTS="$TMPDIR/entitlements.plist"
mkdir -p "$APP"

/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.erikssonhou.leximemory' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0.0' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations~ipad array' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations~ipad:0 string UIInterfaceOrientationPortrait' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations~ipad:1 string UIInterfaceOrientationPortraitUpsideDown' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations~ipad:2 string UIInterfaceOrientationLandscapeLeft' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :UISupportedInterfaceOrientations~ipad:3 string UIInterfaceOrientationLandscapeRight' "$APP/Info.plist"

/usr/libexec/PlistBuddy -c 'Clear dict' "$ENTITLEMENTS" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-identifiers array' "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-container-identifiers:0 string iCloud.com.erikssonhou.leximemory' "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-services array' "$ENTITLEMENTS"
/usr/libexec/PlistBuddy -c 'Add :com.apple.developer.icloud-services:0 string CloudKit' "$ENTITLEMENTS"

OUTPUT="$("$ROOT/scripts/collect_release_candidate_evidence.sh" --platform ios --app "$APP" --entitlements "$ENTITLEMENTS")"

grep -qF '| Candidate build | iOS |' <<<"$OUTPUT"
grep -qF '| Bundle ID | com.erikssonhou.leximemory |' <<<"$OUTPUT"
grep -qF '| Version | 1.0.0 |' <<<"$OUTPUT"
grep -qF '| Build | 1 |' <<<"$OUTPUT"
grep -qF '| iPad orientations | UIInterfaceOrientationPortrait, UIInterfaceOrientationPortraitUpsideDown, UIInterfaceOrientationLandscapeLeft, UIInterfaceOrientationLandscapeRight |' <<<"$OUTPUT"
grep -qF '| CloudKit containers | iCloud.com.erikssonhou.leximemory |' <<<"$OUTPUT"
grep -qF '| iCloud services | CloudKit |' <<<"$OUTPUT"
