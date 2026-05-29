#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
PASSING_EVIDENCE="$TMPDIR/passing-evidence.md"
INCOMPLETE_EVIDENCE="$TMPDIR/incomplete-evidence.md"
MISSING_COMMIT_EVIDENCE="$TMPDIR/missing-commit-evidence.md"

cat >"$PASSING_EVIDENCE" <<'PASSING_MD'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | all non-manual gates passed |
| Candidate gate | macOS + iOS | local build host | 1 | PASS | all requested signed candidates built |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | macOS signed candidate |
| Candidate build | iOS | local build host | 1 | PASS | iOS signed candidate |

## Manual Smoke Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Translation loop | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | translated and relaunched |
| Translation loop | iPhone | iPhone 17 Pro Max / iOS 26.0 | 1 | PASS | translated and relaunched |
| Translation loop | iPad | iPad Pro 11-inch / iPadOS 26.0 | 1 | PASS | translated and relaunched |
| Import/export | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | exported and imported |
| Import/export | iOS/iPadOS | iPad Pro 11-inch / iPadOS 26.0 | 1 | PASS | exported and imported |
| Local recovery | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | backup and reset scoped |
| Local recovery | iOS/iPadOS | iPhone 17 Pro Max / iOS 26.0 | 1 | PASS | backup and reset scoped |
| iCloud create sync | iPhone + macOS | iPhone 17 Pro Max + MacBook Pro | 1 | PASS | created item synced |
| iCloud delete sync | iPhone + macOS | iPhone 17 Pro Max + MacBook Pro | 1 | PASS | deletion synced |
| Local-only fallback | macOS/iOS | MacBook Pro + iPhone 17 Pro Max | 1 | PASS | local mode stayed usable |
PASSING_MD

cp "$PASSING_EVIDENCE" "$MISSING_COMMIT_EVIDENCE"
cat >>"$PASSING_EVIDENCE" <<COMMIT_MD

| Field | Value |
| --- | --- |
| Git commit | $CURRENT_COMMIT |
COMMIT_MD

"$ROOT/scripts/check_release_completion.sh" --evidence "$PASSING_EVIDENCE" \
  >/tmp/wordscene-completion-pass.out 2>/tmp/wordscene-completion-pass.err
grep -qF 'Release completion evidence is complete.' /tmp/wordscene-completion-pass.out

cat >"$INCOMPLETE_EVIDENCE" <<'INCOMPLETE_MD'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | all non-manual gates passed |
| Candidate gate | macOS + iOS | local build host | 1 | BLOCKED | macOS signing blocked |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | iOS signed candidate |

## Manual Smoke Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Translation loop | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | translated and relaunched |
| Translation loop | iPhone | iPhone 17 Pro Max / iOS 26.0 | 1 | PASS | translated and relaunched |
INCOMPLETE_MD

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$INCOMPLETE_EVIDENCE" \
  >/tmp/wordscene-completion-fail.out 2>/tmp/wordscene-completion-fail.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Blocking evidence still present: Candidate gate / macOS + iOS / BLOCKED' /tmp/wordscene-completion-fail.err
grep -qF 'Missing PASS evidence: Candidate build / macOS' /tmp/wordscene-completion-fail.err
grep -qF 'Missing PASS evidence: Translation loop / iPad' /tmp/wordscene-completion-fail.err
grep -qF 'Missing PASS evidence: iCloud create sync / iPhone + macOS' /tmp/wordscene-completion-fail.err

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$MISSING_COMMIT_EVIDENCE" \
  >/tmp/wordscene-completion-missing-commit.out 2>/tmp/wordscene-completion-missing-commit.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Missing candidate build Git commit metadata.' /tmp/wordscene-completion-missing-commit.err
