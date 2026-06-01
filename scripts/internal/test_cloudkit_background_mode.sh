#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! /usr/libexec/PlistBuddy -c 'Print :UIBackgroundModes:0' "$ROOT/WordScene/Generated/WordSceneInfo.plist" 2>/dev/null | rg -n '^remote-notification$' >/tmp/wordscene-cloudkit-background-project.out; then
  echo "iOS target uses CloudKit but the generated Info.plist does not declare remote-notification background mode." >&2
  exit 1
fi

if ! rg -n 'INFOPLIST_FILE = WordScene/Generated/WordSceneInfo.plist;' "$ROOT/WordScene.xcodeproj/project.pbxproj" >/tmp/wordscene-cloudkit-background-pbxproj.out; then
  echo "iOS target uses CloudKit but the generated Xcode project does not use the generated Info.plist." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :aps-environment' "$ROOT/WordScene/WordSceneiOS.entitlements" >/tmp/wordscene-ios-aps.out 2>/dev/null; then
  echo "iOS target uses CloudKit but the iOS entitlements do not declare aps-environment." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' "$ROOT/WordScene/WordSceneMac.entitlements" >/tmp/wordscene-macos-aps.out 2>/dev/null; then
  echo "macOS target uses CloudKit but the macOS entitlements do not declare com.apple.developer.aps-environment." >&2
  exit 1
fi

if ! rg -n 'CODE_SIGN_ENTITLEMENTS = WordScene/WordSceneiOS.entitlements;' "$ROOT/WordScene.xcodeproj/project.pbxproj" >/tmp/wordscene-ios-entitlements-pbxproj.out; then
  echo "Generated Xcode project does not point the iOS target at WordSceneiOS.entitlements." >&2
  exit 1
fi

if ! rg -n 'CODE_SIGN_ENTITLEMENTS = WordScene/WordSceneMac.entitlements;' "$ROOT/WordScene.xcodeproj/project.pbxproj" >/tmp/wordscene-macos-entitlements-pbxproj.out; then
  echo "Generated Xcode project does not point the macOS target at WordSceneMac.entitlements." >&2
  exit 1
fi
