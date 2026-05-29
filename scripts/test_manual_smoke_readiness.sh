#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
EVIDENCE="$TMPDIR/release-smoke-evidence.md"

cat >"$EVIDENCE" <<EVIDENCE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | readiness passed |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | macOS signing blocked |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live smoke passed. Git commit \`$CURRENT_COMMIT\`. |

## Release Candidate Build Blocker

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | BLOCKED | missing profile |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | signed iOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
EVIDENCE_MD

"$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE" >"$TMPDIR/readiness.out"

grep -qF 'READY Translation loop / iPhone' "$TMPDIR/readiness.out"
grep -qF 'READY Translation loop / iPad' "$TMPDIR/readiness.out"
grep -qF 'READY Import/export / iOS/iPadOS' "$TMPDIR/readiness.out"
grep -qF 'READY Local recovery / iOS/iPadOS' "$TMPDIR/readiness.out"
grep -qF 'READY Local-only fallback / macOS/iOS' "$TMPDIR/readiness.out"
grep -qF 'WAITING Translation loop / macOS - missing PASS candidate build: macOS' "$TMPDIR/readiness.out"
grep -qF 'WAITING iCloud create sync / iPhone + macOS - missing PASS candidate build: macOS' "$TMPDIR/readiness.out"
grep -qF 'WAITING iCloud delete sync / iPhone + macOS - missing PASS candidate build: macOS' "$TMPDIR/readiness.out"
