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

"$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE" --commands >"$TMPDIR/commands.out"

grep -qF 'READY Translation loop / iPhone' "$TMPDIR/commands.out"
grep -qF 'scripts/record_release_smoke_result.sh \' "$TMPDIR/commands.out"
grep -qF '  --area "Translation loop" \' "$TMPDIR/commands.out"
grep -qF '  --platform "iPhone" \' "$TMPDIR/commands.out"
grep -qF '  --build "1" \' "$TMPDIR/commands.out"
grep -qF '  --notes "<manual smoke notes>"' "$TMPDIR/commands.out"
if grep -qF -- '--platform "macOS"' "$TMPDIR/commands.out"; then
  echo "manual_smoke_readiness --commands should not print blocked macOS record commands" >&2
  exit 1
fi

WORDSCENE_CURRENT_COMMIT="abcdef123456" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE="scripts/run_release_candidate_gate.sh" \
"$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$EVIDENCE" --commands >"$TMPDIR/stale-candidate.out"

grep -qF 'WAITING Translation loop / iPhone - fresh release candidate evidence required: scripts/run_release_candidate_gate.sh changed after candidate build' "$TMPDIR/stale-candidate.out"
if grep -qF 'scripts/record_release_smoke_result.sh \' "$TMPDIR/stale-candidate.out"; then
  echo "manual_smoke_readiness --commands should not print commands when candidate evidence is stale" >&2
  exit 1
fi

LIVE_STALE_EVIDENCE="$TMPDIR/release-smoke-evidence-live-stale.md"
cat >"$LIVE_STALE_EVIDENCE" <<EVIDENCE_MD
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
| Git commit | abcdef123456 |
EVIDENCE_MD

WORDSCENE_CURRENT_COMMIT="abcdef123456" \
WORDSCENE_LIVE_SMOKE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE="scripts/run_live_deepseek_translation_smoke.sh" \
"$ROOT/scripts/manual_smoke_readiness.sh" --evidence "$LIVE_STALE_EVIDENCE" --commands >"$TMPDIR/stale-live.out"

grep -qF 'WAITING Translation loop / iPhone - fresh DeepSeek live protocol smoke required: scripts/run_live_deepseek_translation_smoke.sh changed after live smoke' "$TMPDIR/stale-live.out"
if grep -qF 'scripts/record_release_smoke_result.sh \' "$TMPDIR/stale-live.out"; then
  echo "manual_smoke_readiness --commands should not print commands when live smoke evidence is stale" >&2
  exit 1
fi
