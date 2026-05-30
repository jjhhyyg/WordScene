#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BIN="$TMPDIR/bin"
LOG="$TMPDIR/xcodebuild.log"
mkdir -p "$BIN"

cat >"$BIN/xcodebuild" <<'FAKE_XCODEBUILD'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcodebuild %s\n' "$*" >>"$WORDSCENE_SCHEMA_TEST_LOG"
if [[ "$*" == *"build-for-testing"* ]]; then
  derived_data=""
  previous=""
  for argument in "$@"; do
    if [[ "$previous" == "-derivedDataPath" ]]; then
      derived_data="$argument"
      break
    fi
    previous="$argument"
  done
  if [[ -z "$derived_data" ]]; then
    echo "fake xcodebuild expected -derivedDataPath" >&2
    exit 1
  fi
  mkdir -p "$derived_data/Build/Products"
  cat >"$derived_data/Build/Products/Fake.xctestrun" <<'FAKE_XCTESTRUN'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>WordSceneTests</key>
  <dict>
    <key>TestingEnvironmentVariables</key>
    <dict/>
  </dict>
</dict>
</plist>
FAKE_XCTESTRUN
fi
FAKE_XCODEBUILD
chmod +x "$BIN/xcodebuild"

PATH="$BIN:$PATH" WORDSCENE_SCHEMA_TEST_LOG="$LOG" \
  "$ROOT/scripts/initialize_cloudkit_schema.sh" --platform ios --device 00008150-000A42D90A3B401C --dry-run --print-schema

grep -qF 'xcodebuild build-for-testing -project' "$LOG"
grep -qF -- '-scheme WordScene' "$LOG"
grep -qF -- '-destination id=00008150-000A42D90A3B401C' "$LOG"
grep -qF -- '-only-testing:WordSceneTests/CloudKitSchemaInitializationTests/testInitializeCloudKitDevelopmentSchema' "$LOG"
grep -qF 'xcodebuild test-without-building -xctestrun' "$LOG"

if PATH="$BIN:$PATH" WORDSCENE_SCHEMA_TEST_LOG="$LOG" \
  "$ROOT/scripts/initialize_cloudkit_schema.sh" --platform ios >/tmp/wordscene-schema-ios-without-device.out 2>/tmp/wordscene-schema-ios-without-device.err; then
  echo "Expected iOS schema initialization without --device to fail." >&2
  exit 1
fi
grep -qF 'iOS schema initialization requires --device <identifier>' /tmp/wordscene-schema-ios-without-device.err
