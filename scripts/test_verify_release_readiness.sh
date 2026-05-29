#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BIN="$TMPDIR/bin"
LOG="$TMPDIR/commands.log"
mkdir -p "$BIN"

cat >"$BIN/git" <<'FAKE_GIT'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"$WORDSCENE_FAKE_COMMAND_LOG"
if [[ "$1" == "diff" && "${2:-}" == "--check" ]]; then
  exit 0
fi
if [[ "$1" == "-C" && "${3:-}" == "rev-parse" && "${4:-}" == "--short=12" && "${5:-}" == "HEAD" ]]; then
  printf 'abc123def456\n'
  exit 0
fi
echo "unexpected git invocation: $*" >&2
exit 70
FAKE_GIT

cat >"$BIN/rg" <<'FAKE_RG'
#!/usr/bin/env bash
set -euo pipefail
printf 'rg %s\n' "$*" >>"$WORDSCENE_FAKE_COMMAND_LOG"
token_pattern='sk-[A-Za-z0-9]|e2a'
token_pattern+='988'
xcode_pattern='LastUpgradeCheck = 1430|LastUpgradeVersion = "1430"'
case "$*" in
  *"$token_pattern"*|*"$xcode_pattern"*)
    exit 1
    ;;
  *)
    echo "unexpected rg invocation: $*" >&2
    exit 70
    ;;
esac
FAKE_RG

cat >"$BIN/xcodebuild" <<'FAKE_XCODEBUILD'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcodebuild %s\n' "$*" >>"$WORDSCENE_FAKE_COMMAND_LOG"
exit 0
FAKE_XCODEBUILD

cat >"$BIN/scripts-test-run-release-candidate-gate" <<'FAKE_GATE_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_run_release_candidate_gate\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_GATE_TEST

cat >"$BIN/scripts-test-run-live-deepseek-translation-smoke" <<'FAKE_LIVE_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_run_live_deepseek_translation_smoke\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_LIVE_TEST

cat >"$BIN/scripts-test-check-release-completion" <<'FAKE_COMPLETION_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_check_release_completion\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_COMPLETION_TEST

cat >"$BIN/scripts-test-manual-smoke-readiness" <<'FAKE_MANUAL_SMOKE_READINESS_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_manual_smoke_readiness\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_MANUAL_SMOKE_READINESS_TEST

cat >"$BIN/scripts-test-release-next-actions" <<'FAKE_RELEASE_NEXT_ACTIONS_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_release_next_actions\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_RELEASE_NEXT_ACTIONS_TEST

cat >"$BIN/scripts-test-privacy-manifest" <<'FAKE_PRIVACY_MANIFEST_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_privacy_manifest\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_PRIVACY_MANIFEST_TEST

cat >"$BIN/scripts-test-privacy-surface" <<'FAKE_PRIVACY_SURFACE_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_privacy_surface\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_PRIVACY_SURFACE_TEST

cat >"$BIN/scripts-test-cloudkit-background-mode" <<'FAKE_CLOUDKIT_BACKGROUND_MODE_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_cloudkit_background_mode\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_CLOUDKIT_BACKGROUND_MODE_TEST

cat >"$BIN/scripts-test-required-reason-api-scan" <<'FAKE_REQUIRED_REASON_API_SCAN'
#!/usr/bin/env bash
set -euo pipefail
printf 'test_required_reason_api_scan\n' >>"$WORDSCENE_FAKE_COMMAND_LOG"
FAKE_REQUIRED_REASON_API_SCAN

chmod +x "$BIN/git" "$BIN/rg" "$BIN/xcodebuild" "$BIN/scripts-test-run-release-candidate-gate" "$BIN/scripts-test-run-live-deepseek-translation-smoke" "$BIN/scripts-test-check-release-completion" "$BIN/scripts-test-manual-smoke-readiness" "$BIN/scripts-test-release-next-actions" "$BIN/scripts-test-privacy-manifest" "$BIN/scripts-test-privacy-surface" "$BIN/scripts-test-cloudkit-background-mode" "$BIN/scripts-test-required-reason-api-scan"

PATH="$BIN:$PATH" \
  WORDSCENE_FAKE_COMMAND_LOG="$LOG" \
  WORDSCENE_SKIP_READINESS_SELF_TEST=1 \
  WORDSCENE_TEST_RUN_CANDIDATE_GATE_SCRIPT="$BIN/scripts-test-run-release-candidate-gate" \
  WORDSCENE_TEST_RUN_LIVE_DEEPSEEK_TRANSLATION_SMOKE_SCRIPT="$BIN/scripts-test-run-live-deepseek-translation-smoke" \
  WORDSCENE_TEST_CHECK_RELEASE_COMPLETION_SCRIPT="$BIN/scripts-test-check-release-completion" \
  WORDSCENE_TEST_MANUAL_SMOKE_READINESS_SCRIPT="$BIN/scripts-test-manual-smoke-readiness" \
  WORDSCENE_TEST_RELEASE_NEXT_ACTIONS_SCRIPT="$BIN/scripts-test-release-next-actions" \
  WORDSCENE_TEST_PRIVACY_MANIFEST_SCRIPT="$BIN/scripts-test-privacy-manifest" \
  WORDSCENE_TEST_PRIVACY_SURFACE_SCRIPT="$BIN/scripts-test-privacy-surface" \
  WORDSCENE_TEST_CLOUDKIT_BACKGROUND_MODE_SCRIPT="$BIN/scripts-test-cloudkit-background-mode" \
  WORDSCENE_TEST_REQUIRED_REASON_API_SCAN_SCRIPT="$BIN/scripts-test-required-reason-api-scan" \
  "$ROOT/scripts/verify_release_readiness.sh"

grep -qF 'git diff --check' "$LOG"
grep -qF 'test_run_release_candidate_gate' "$LOG"
grep -qF 'test_run_live_deepseek_translation_smoke' "$LOG"
grep -qF 'test_check_release_completion' "$LOG"
grep -qF 'test_manual_smoke_readiness' "$LOG"
grep -qF 'test_release_next_actions' "$LOG"
grep -qF 'test_privacy_manifest' "$LOG"
grep -qF 'test_privacy_surface' "$LOG"
grep -qF 'test_cloudkit_background_mode' "$LOG"
grep -qF 'test_required_reason_api_scan' "$LOG"
token_pattern='sk-[A-Za-z0-9]|e2a'
token_pattern+='988'
grep -qF "rg -n $token_pattern WordScene docs project.yml .gitignore scripts" "$LOG"
grep -qF 'rg -n LastUpgradeCheck = 1430|LastUpgradeVersion = "1430" WordScene.xcodeproj/project.pbxproj WordScene.xcodeproj/xcshareddata/xcschemes/WordScene.xcscheme WordScene.xcodeproj/xcshareddata/xcschemes/WordSceneMac.xcscheme' "$LOG"
grep -qF "xcodebuild test -project WordScene.xcodeproj -scheme WordSceneMac -destination platform=macOS -derivedDataPath /tmp/WordSceneVerifyMac CODE_SIGNING_ALLOWED=NO" "$LOG"
grep -qF "xcodebuild test -project WordScene.xcodeproj -scheme WordScene -destination platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.5 -derivedDataPath /tmp/WordSceneVerifyIOSTests CODE_SIGNING_ALLOWED=NO" "$LOG"
grep -qF "xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination generic/platform=iOS -derivedDataPath /tmp/WordSceneVerifyIOS CODE_SIGNING_ALLOWED=NO" "$LOG"
grep -qF "xcodebuild build -project WordScene.xcodeproj -scheme WordSceneMac -configuration Release -destination platform=macOS -derivedDataPath /tmp/WordSceneVerifyReleaseMac CODE_SIGNING_ALLOWED=NO" "$LOG"
grep -qF "xcodebuild build -project WordScene.xcodeproj -scheme WordScene -configuration Release -destination generic/platform=iOS -derivedDataPath /tmp/WordSceneVerifyReleaseIOS CODE_SIGNING_ALLOWED=NO" "$LOG"
