#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

CURRENT_COMMIT="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
EVIDENCE="$TMPDIR/release-smoke-evidence.md"
MISSING_CANDIDATE_EVIDENCE="$TMPDIR/missing-candidate-evidence.md"
STALE_CANDIDATE_EVIDENCE="$TMPDIR/stale-candidate-evidence.md"
ANCESTOR_DOCS_ONLY_CANDIDATE_EVIDENCE="$TMPDIR/ancestor-docs-only-candidate-evidence.md"
ANCESTOR_PRODUCT_CHANGE_CANDIDATE_EVIDENCE="$TMPDIR/ancestor-product-change-candidate-evidence.md"
IOS_ONLY_CANDIDATE_EVIDENCE="$TMPDIR/ios-only-candidate-evidence.md"
MISSING_LIVE_SMOKE_EVIDENCE="$TMPDIR/missing-live-smoke-evidence.md"
STALE_LIVE_SMOKE_EVIDENCE="$TMPDIR/stale-live-smoke-evidence.md"
MISMATCHED_BUILD_EVIDENCE="$TMPDIR/mismatched-build-evidence.md"

cat >"$EVIDENCE" <<EVIDENCE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed. Git commit \`$CURRENT_COMMIT\`. |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | signed macOS candidate |
| Candidate build | iOS | local build host | 1 | PASS | signed iOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
EVIDENCE_MD

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --notes "Should require explicit execution confirmation." >"$TMPDIR/missing-confirm.out" 2>"$TMPDIR/missing-confirm.err"
status=$?
set -e

test "$status" -eq 64
grep -qF 'Manual PASS/FAIL smoke evidence requires --confirm-executed' "$TMPDIR/missing-confirm.err"
if grep -qF '## Manual Smoke Evidence' "$EVIDENCE"; then
  echo "record_release_smoke_result should not write PASS rows without explicit execution confirmation" >&2
  exit 1
fi

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
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
  --confirm-executed \
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
  --confirm-executed \
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
  --confirm-executed \
  --notes "Non-canonical platform should be rejected" >"$TMPDIR/invalid-platform.out" 2>"$TMPDIR/invalid-platform.err"
status=$?
set -e

test "$status" -eq 64
grep -qF 'Unsupported manual smoke area/platform' "$TMPDIR/invalid-platform.err"

cat >"$MISSING_CANDIDATE_EVIDENCE" <<'MISSING_CANDIDATE_MD'
## Non-Manual Release Gate

Existing gate evidence without candidate metadata.
MISSING_CANDIDATE_MD

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$MISSING_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should require candidate evidence first" >"$TMPDIR/missing-candidate.out" 2>"$TMPDIR/missing-candidate.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires current release candidate metadata.' "$TMPDIR/missing-candidate.err"
if grep -qF '## Manual Smoke Evidence' "$MISSING_CANDIDATE_EVIDENCE"; then
  echo "record_release_smoke_result should not write manual rows without candidate metadata" >&2
  exit 1
fi

cp "$EVIDENCE" "$MISMATCHED_BUILD_EVIDENCE"

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$MISMATCHED_BUILD_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "2" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should require the current candidate build number" >"$TMPDIR/mismatched-build.out" 2>"$TMPDIR/mismatched-build.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires build 1, got 2.' "$TMPDIR/mismatched-build.err"

cat >"$MISSING_LIVE_SMOKE_EVIDENCE" <<MISSING_LIVE_SMOKE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | readiness passed |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | signed macOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
MISSING_LIVE_SMOKE_MD

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$MISSING_LIVE_SMOKE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should require live API smoke first" >"$TMPDIR/missing-live-smoke.out" 2>"$TMPDIR/missing-live-smoke.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires current DeepSeek live protocol smoke metadata.' "$TMPDIR/missing-live-smoke.err"
if grep -qF '## Manual Smoke Evidence' "$MISSING_LIVE_SMOKE_EVIDENCE"; then
  echo "record_release_smoke_result should not write manual rows without live API smoke metadata" >&2
  exit 1
fi

cp "$EVIDENCE" "$ANCESTOR_DOCS_ONLY_CANDIDATE_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | aaaaaaaaaaaa |/" "$ANCESTOR_DOCS_ONLY_CANDIDATE_EVIDENCE"

WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE=$'docs/release-smoke-evidence.md\ndocs/implementation-plan.md' \
WORDSCENE_LIVE_SMOKE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE=$'docs/release-smoke-evidence.md\ndocs/implementation-plan.md' \
  "$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$ANCESTOR_DOCS_ONLY_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Manual smoke can be recorded after evidence-only commits."

grep -qF '| Translation loop | macOS | MacBook Pro / macOS 26.5 | 1 | PASS | Manual smoke can be recorded after evidence-only commits. |' "$ANCESTOR_DOCS_ONLY_CANDIDATE_EVIDENCE"

cp "$EVIDENCE" "$ANCESTOR_PRODUCT_CHANGE_CANDIDATE_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | aaaaaaaaaaaa |/" "$ANCESTOR_PRODUCT_CHANGE_CANDIDATE_EVIDENCE"

set +e
WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_CANDIDATE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_CANDIDATE=$'docs/release-smoke-evidence.md\nscripts/run_release_candidate_gate.sh' \
WORDSCENE_LIVE_SMOKE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE=$'docs/release-smoke-evidence.md\ndocs/implementation-plan.md' \
  "$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$ANCESTOR_PRODUCT_CHANGE_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should reject candidate drift across script changes" >"$TMPDIR/ancestor-product-change.out" 2>"$TMPDIR/ancestor-product-change.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires fresh release candidate metadata; release-critical files changed since candidate build: scripts/run_release_candidate_gate.sh. Rerun scripts/run_release_candidate_gate.sh.' "$TMPDIR/ancestor-product-change.err"

cat >"$STALE_LIVE_SMOKE_EVIDENCE" <<STALE_LIVE_SMOKE_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed. Git commit \`aaaaaaaaaaaa\`. |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | macOS | local build host | 1 | PASS | signed macOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | bbbbbbbbbbbb |
STALE_LIVE_SMOKE_MD

set +e
WORDSCENE_CURRENT_COMMIT="bbbbbbbbbbbb" \
WORDSCENE_LIVE_SMOKE_IS_ANCESTOR=1 \
WORDSCENE_CHANGED_FILES_SINCE_LIVE_SMOKE=$'docs/release-smoke-evidence.md\nscripts/run_live_deepseek_translation_smoke.sh' \
  "$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$STALE_LIVE_SMOKE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro / macOS 26.5" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should reject live API drift across script changes" >"$TMPDIR/stale-live-smoke.out" 2>"$TMPDIR/stale-live-smoke.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires fresh DeepSeek live protocol smoke metadata; release-critical files changed since live API smoke: scripts/run_live_deepseek_translation_smoke.sh. Rerun scripts/run_live_deepseek_translation_smoke.sh.' "$TMPDIR/stale-live-smoke.err"

cp "$EVIDENCE" "$STALE_CANDIDATE_EVIDENCE"
sed -i '' "s/| Git commit | $CURRENT_COMMIT |/| Git commit | 000000000000 |/" "$STALE_CANDIDATE_EVIDENCE"

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$STALE_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Should reject stale candidate evidence" >"$TMPDIR/stale-candidate.out" 2>"$TMPDIR/stale-candidate.err"
status=$?
set -e

test "$status" -eq 1
grep -qF "Manual smoke evidence requires current release candidate metadata: evidence 000000000000 is not an ancestor of current $CURRENT_COMMIT." "$TMPDIR/stale-candidate.err"

cat >"$IOS_ONLY_CANDIDATE_EVIDENCE" <<IOS_ONLY_MD
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | live JSON Output smoke passed. Git commit \`$CURRENT_COMMIT\`. |

## Release Candidate Build Evidence

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Candidate build | iOS | local build host | 1 | PASS | signed iOS candidate |

| Field | Value |
| --- | --- |
| Build | 1 |
| Git commit | $CURRENT_COMMIT |
IOS_ONLY_MD

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$IOS_ONLY_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "iPhone" \
  --device "iPhone 17 Pro Max / iOS 26.0" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "iPhone smoke can use the iOS candidate."

grep -qF '| Translation loop | iPhone | iPhone 17 Pro Max / iOS 26.0 | 1 | PASS | iPhone smoke can use the iOS candidate. |' "$IOS_ONLY_CANDIDATE_EVIDENCE"

"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$IOS_ONLY_CANDIDATE_EVIDENCE" \
  --area "Local-only fallback" \
  --platform "macOS/iOS" \
  --device "Unsigned Mac Release + iPhone 17 Pro Max / iOS 26.0" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "Local-only fallback uses the readiness-covered unsigned Mac build and the signed iOS candidate."

grep -qF '| Local-only fallback | macOS/iOS | Unsigned Mac Release + iPhone 17 Pro Max / iOS 26.0 | 1 | PASS | Local-only fallback uses the readiness-covered unsigned Mac build and the signed iOS candidate. |' "$IOS_ONLY_CANDIDATE_EVIDENCE"

set +e
"$ROOT/scripts/record_release_smoke_result.sh" \
  --evidence "$IOS_ONLY_CANDIDATE_EVIDENCE" \
  --area "Translation loop" \
  --platform "macOS" \
  --device "MacBook Pro" \
  --build "1" \
  --result "PASS" \
  --confirm-executed \
  --notes "macOS smoke should require a macOS candidate." >"$TMPDIR/missing-macos-build.out" 2>"$TMPDIR/missing-macos-build.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'Manual smoke evidence requires PASS candidate build evidence for: macOS.' "$TMPDIR/missing-macos-build.err"
if grep -qF '| Translation loop | macOS |' "$IOS_ONLY_CANDIDATE_EVIDENCE"; then
  echo "record_release_smoke_result should not write macOS smoke rows without macOS candidate evidence" >&2
  exit 1
fi

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
