#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/WordScene/Resources/PrivacyInfo.xcprivacy"

test -f "$MANIFEST"
plutil -lint "$MANIFEST" >/tmp/wordscene-privacy-manifest-lint.out

api_type="$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPIType raw -o - "$MANIFEST")"
reason="$(plutil -extract NSPrivacyAccessedAPITypes.0.NSPrivacyAccessedAPITypeReasons.0 raw -o - "$MANIFEST")"

test "$api_type" = "NSPrivacyAccessedAPICategoryUserDefaults"
test "$reason" = "CA92.1"
test "$(grep -c 'PrivacyInfo.xcprivacy in Resources' "$ROOT/WordScene.xcodeproj/project.pbxproj")" -ge 4

if plutil -extract NSPrivacyCollectedDataTypes raw -o - "$MANIFEST" >/tmp/wordscene-privacy-collected.out 2>/tmp/wordscene-privacy-collected.err; then
  echo "Privacy manifest should not declare collected data until App Store privacy answers are finalized." >&2
  exit 1
fi
