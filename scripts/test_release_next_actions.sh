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

"$ROOT/scripts/release_next_actions.sh" --evidence "$EVIDENCE" >"$TMPDIR/actions.out"

grep -qF 'Release Next Actions' "$TMPDIR/actions.out"
grep -qF '1. Restore macOS signing before macOS and iCloud smoke.' "$TMPDIR/actions.out"
grep -qF 'scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all' "$TMPDIR/actions.out"
grep -qF '2. READY manual smoke rows that can be run now:' "$TMPDIR/actions.out"
grep -qF -- '- Translation loop / iPhone' "$TMPDIR/actions.out"
grep -qF -- '- Import/export / iOS/iPadOS' "$TMPDIR/actions.out"
grep -qF -- '- Local-only fallback / macOS/iOS' "$TMPDIR/actions.out"
grep -qF '3. Do not call the release complete until scripts/check_release_completion.sh passes.' "$TMPDIR/actions.out"
