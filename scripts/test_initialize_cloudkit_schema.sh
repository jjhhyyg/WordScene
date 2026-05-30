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
printf 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA=%s\n' "${WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA:-}" >>"$WORDSCENE_SCHEMA_TEST_LOG"
printf 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN=%s\n' "${WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN:-}" >>"$WORDSCENE_SCHEMA_TEST_LOG"
printf 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT=%s\n' "${WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT:-}" >>"$WORDSCENE_SCHEMA_TEST_LOG"
printf 'xcodebuild %s\n' "$*" >>"$WORDSCENE_SCHEMA_TEST_LOG"
FAKE_XCODEBUILD
chmod +x "$BIN/xcodebuild"

PATH="$BIN:$PATH" WORDSCENE_SCHEMA_TEST_LOG="$LOG" \
  "$ROOT/scripts/initialize_cloudkit_schema.sh" --platform ios --device 00008150-000A42D90A3B401C --dry-run --print-schema

grep -qF 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA=1' "$LOG"
grep -qF 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN=1' "$LOG"
grep -qF 'WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT=1' "$LOG"
grep -qF 'xcodebuild test -project' "$LOG"
grep -qF -- '-scheme WordScene' "$LOG"
grep -qF -- '-destination id=00008150-000A42D90A3B401C' "$LOG"
grep -qF -- '-only-testing:WordSceneTests/CloudKitSchemaInitializationTests/testInitializeCloudKitDevelopmentSchema' "$LOG"

if PATH="$BIN:$PATH" WORDSCENE_SCHEMA_TEST_LOG="$LOG" \
  "$ROOT/scripts/initialize_cloudkit_schema.sh" --platform ios >/tmp/wordscene-schema-ios-without-device.out 2>/tmp/wordscene-schema-ios-without-device.err; then
  echo "Expected iOS schema initialization without --device to fail." >&2
  exit 1
fi
grep -qF 'iOS schema initialization requires --device <identifier>' /tmp/wordscene-schema-ios-without-device.err
