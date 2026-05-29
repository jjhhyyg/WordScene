#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
PASSING_EVIDENCE="$TMPDIR/passing-evidence.md"
INCOMPLETE_EVIDENCE="$TMPDIR/incomplete-evidence.md"
MISSING_COMMIT_EVIDENCE="$TMPDIR/missing-commit-evidence.md"
STALE_COMMIT_EVIDENCE="$TMPDIR/stale-commit-evidence.md"
MISSING_LIVE_COMMIT_EVIDENCE="$TMPDIR/missing-live-commit-evidence.md"
ANCESTOR_DOCS_ONLY_EVIDENCE="$TMPDIR/ancestor-docs-only-evidence.md"
ANCESTOR_PRODUCT_CHANGE_EVIDENCE="$TMPDIR/ancestor-product-change-evidence.md"
NON_ANCESTOR_EVIDENCE="$TMPDIR/non-ancestor-evidence.md"
DUPLICATE_PASS_EVIDENCE="$TMPDIR/duplicate-pass-evidence.md"
MALFORMED_TABLE_EVIDENCE="$TMPDIR/malformed-table-evidence.md"

cat >"$PASSING_EVIDENCE" <<'PASSING_MD'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | all non-manual gates passed |
| Candidate gate | macOS + iOS | local build host | 1 | PASS | all requested signed candidates built |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed. Git commit PLACEHOLDER_COMMIT. |

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
cp "$PASSING_EVIDENCE" "$MISSING_LIVE_COMMIT_EVIDENCE"
sed -i '' 's/ Git commit PLACEHOLDER_COMMIT//' "$MISSING_LIVE_COMMIT_EVIDENCE"
sed -i '' "s/PLACEHOLDER_COMMIT/\`$CURRENT_COMMIT\`/" "$PASSING_EVIDENCE"
cat >>"$PASSING_EVIDENCE" <<COMMIT_MD

| Field | Value |
| --- | --- |
| Git commit | $CURRENT_COMMIT |
COMMIT_MD

"$ROOT/scripts/check_release_completion.sh" --evidence "$PASSING_EVIDENCE" \
  >/tmp/wordscene-completion-pass.out 2>/tmp/wordscene-completion-pass.err
grep -qF 'Release completion evidence is complete.' /tmp/wordscene-completion-pass.out

cp "$PASSING_EVIDENCE" "$ANCESTOR_DOCS_ONLY_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | aaaaaaaaaaaa |/" "$ANCESTOR_DOCS_ONLY_EVIDENCE"

WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE=$'docs/release-smoke-evidence.md\ndocs/implementation-plan.md' \
  "$ROOT/scripts/check_release_completion.sh" --evidence "$ANCESTOR_DOCS_ONLY_EVIDENCE" \
  >/tmp/wordscene-completion-ancestor-docs-only.out 2>/tmp/wordscene-completion-ancestor-docs-only.err
grep -qF 'Release completion evidence is complete.' /tmp/wordscene-completion-ancestor-docs-only.out

cp "$PASSING_EVIDENCE" "$ANCESTOR_PRODUCT_CHANGE_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | aaaaaaaaaaaa |/" "$ANCESTOR_PRODUCT_CHANGE_EVIDENCE"

set +e
WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE=$'docs/release-smoke-evidence.md\nWordScene/Sources/Features/TranslateView.swift' \
  "$ROOT/scripts/check_release_completion.sh" --evidence "$ANCESTOR_PRODUCT_CHANGE_EVIDENCE" \
  >/tmp/wordscene-completion-ancestor-product-change.out 2>/tmp/wordscene-completion-ancestor-product-change.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Candidate build Git commit is stale for release-critical files: WordScene/Sources/Features/TranslateView.swift. Rerun scripts/run_release_candidate_gate.sh.' /tmp/wordscene-completion-ancestor-product-change.err

cp "$PASSING_EVIDENCE" "$NON_ANCESTOR_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | aaaaaaaaaaaa |/" "$NON_ANCESTOR_EVIDENCE"

set +e
WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=0 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE='' \
  "$ROOT/scripts/check_release_completion.sh" --evidence "$NON_ANCESTOR_EVIDENCE" \
  >/tmp/wordscene-completion-non-ancestor.out 2>/tmp/wordscene-completion-non-ancestor.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Candidate build Git commit is not an ancestor of current HEAD: evidence aaaaaaaaaaaa, current bbbbbbbbbbbb.' /tmp/wordscene-completion-non-ancestor.err

cp "$PASSING_EVIDENCE" "$DUPLICATE_PASS_EVIDENCE"
cat >>"$DUPLICATE_PASS_EVIDENCE" <<'DUPLICATE_MD'
| Translation loop | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | duplicate stale retest row |
DUPLICATE_MD

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$DUPLICATE_PASS_EVIDENCE" \
  >/tmp/wordscene-completion-duplicate-pass.out 2>/tmp/wordscene-completion-duplicate-pass.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Duplicate PASS evidence: Translation loop / macOS (2 rows)' /tmp/wordscene-completion-duplicate-pass.err

awk '
  /^## Manual Smoke Evidence$/ {
    print
    getline
    print
    getline
    next
  }
  { print }
' "$PASSING_EVIDENCE" >"$MALFORMED_TABLE_EVIDENCE"

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$MALFORMED_TABLE_EVIDENCE" \
  >/tmp/wordscene-completion-malformed-table.out 2>/tmp/wordscene-completion-malformed-table.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Malformed evidence table: Manual Smoke Evidence' /tmp/wordscene-completion-malformed-table.err

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

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$MISSING_LIVE_COMMIT_EVIDENCE" \
  >/tmp/wordscene-completion-missing-live-commit.out 2>/tmp/wordscene-completion-missing-live-commit.err
status=$?
set -e

test "$status" -eq 1
grep -qF 'Missing DeepSeek live protocol smoke Git commit metadata.' /tmp/wordscene-completion-missing-live-commit.err

cp "$PASSING_EVIDENCE" "$STALE_COMMIT_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | 000000000000 |/" "$STALE_COMMIT_EVIDENCE"

set +e
"$ROOT/scripts/check_release_completion.sh" --evidence "$STALE_COMMIT_EVIDENCE" \
  >/tmp/wordscene-completion-stale-commit.out 2>/tmp/wordscene-completion-stale-commit.err
status=$?
set -e

test "$status" -eq 1
grep -qF "Candidate build Git commit is not an ancestor of current HEAD: evidence 000000000000, current $CURRENT_COMMIT." /tmp/wordscene-completion-stale-commit.err
