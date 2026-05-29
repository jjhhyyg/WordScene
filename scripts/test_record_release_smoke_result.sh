#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

EVIDENCE="$TMPDIR/release-smoke-evidence.md"

cat >"$EVIDENCE" <<'EVIDENCE_MD'
## Non-Manual Release Gate

Existing gate evidence.
EVIDENCE_MD

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --notes "Saved token, translated hello world, history survived relaunch."

grep -qF '## Manual Smoke Evidence' "$EVIDENCE"
grep -qF '| Translation loop | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | Saved token, translated hello world, history survived relaunch. |' "$EVIDENCE"

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Import/export" \
  --platform "iOS/iPadOS" \
  --device "iPad Pro 11-inch / iPadOS 26.0" \
  --build "1" \
  --result "BLOCKED" \
  --notes "Awaiting signed build | do not break table"

grep -qF '| Import/export | iOS/iPadOS | iPad Pro 11-inch / iPadOS 26.0 | 1 | BLOCKED | Awaiting signed build / do not break table |' "$EVIDENCE"
test "$(grep -cF '## Manual Smoke Evidence' "$EVIDENCE")" -eq 1

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Import/export" \
  --platform "iOS/iPadOS" \
  --device "iPad Pro 11-inch / iPadOS 26.0" \
  --build "1" \
  --result "PASS" \
  --notes "Retested export and import on the current candidate."

grep -qF '| Import/export | iOS/iPadOS | iPad Pro 11-inch / iPadOS 26.0 | 1 | PASS | Retested export and import on the current candidate. |' "$EVIDENCE"
test "$(grep -cF '| Import/export | iOS/iPadOS |' "$EVIDENCE")" -eq 1
if grep -qF '| Import/export | iOS/iPadOS | iPad Pro 11-inch / iPadOS 26.0 | 1 | BLOCKED |' "$EVIDENCE"; then
  echo "record_release_smoke_result should replace stale rows for the same area/platform" >&2
  exit 1
fi

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Translation loops" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "PASS" \
  --notes "Typo should be rejected" >"$TMPDIR/invalid-area.out" 2>"$TMPDIR/invalid-area.err"
status=$?
set -e

test "$status" -eq 64
grep -qF 'Unsupported manual smoke area/platform' "$TMPDIR/invalid-area.err"

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Import/export" \
  --platform "iPadOS" \
  --device "iPad Pro" \
  --build "1" \
  --result "PASS" \
  --notes "Non-canonical platform should be rejected" >"$TMPDIR/invalid-platform.out" 2>"$TMPDIR/invalid-platform.err"
status=$?
set -e

test "$status" -eq 64
grep -qF 'Unsupported manual smoke area/platform' "$TMPDIR/invalid-platform.err"

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "MAYBE" \
  --notes "Invalid result" >/tmp/wordscene-smoke-record.out 2>/tmp/wordscene-smoke-record.err
status=$?
set -e

test "$status" -eq 64
grep -qF 'Unsupported result' /tmp/wordscene-smoke-record.err
