#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_CANDIDATE_GATE_TEST_SCRIPT="${WORDSCENE_TEST_RUN_CANDIDATE_GATE_SCRIPT:-scripts/test_run_release_candidate_gate.sh}"
RUN_LIVE_DEEPSEEK_TRANSLATION_SMOKE_TEST_SCRIPT="${WORDSCENE_TEST_RUN_LIVE_DEEPSEEK_TRANSLATION_SMOKE_SCRIPT:-scripts/test_run_live_deepseek_translation_smoke.sh}"
CHECK_RELEASE_COMPLETION_TEST_SCRIPT="${WORDSCENE_TEST_CHECK_RELEASE_COMPLETION_SCRIPT:-scripts/test_check_release_completion.sh}"
PRIVACY_MANIFEST_TEST_SCRIPT="${WORDSCENE_TEST_PRIVACY_MANIFEST_SCRIPT:-scripts/test_privacy_manifest.sh}"
PRIVACY_SURFACE_TEST_SCRIPT="${WORDSCENE_TEST_PRIVACY_SURFACE_SCRIPT:-scripts/test_privacy_surface.sh}"
REQUIRED_REASON_API_SCAN_SCRIPT="${WORDSCENE_TEST_REQUIRED_REASON_API_SCAN_SCRIPT:-scripts/test_required_reason_api_scan.sh}"
MANUAL_SMOKE_READINESS_TEST_SCRIPT="${WORDSCENE_TEST_MANUAL_SMOKE_READINESS_SCRIPT:-scripts/test_manual_smoke_readiness.sh}"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

expect_no_matches() {
  local description="$1"
  shift

  printf '\n==> %s\n' "$description"
  set +e
  "$@"
  local status=$?
  set -e

  case "$status" in
    1)
      printf 'No matches.\n'
      ;;
    0)
      printf 'Unexpected matches found for: %s\n' "$description" >&2
      exit 1
      ;;
    *)
      printf 'Command failed while checking: %s\n' "$description" >&2
      exit "$status"
      ;;
  esac
}

cd "$ROOT"

TOKEN_SCAN_PATTERN="sk-[A-Za-z0-9]|e2a"
TOKEN_SCAN_PATTERN+="988"

run bash -n \
  scripts/build_release_candidates.sh \
  scripts/collect_release_candidate_evidence.sh \
  scripts/test_collect_release_candidate_evidence.sh \
  scripts/run_live_deepseek_translation_smoke.sh \
  scripts/test_run_live_deepseek_translation_smoke.sh \
  scripts/diagnose_release_signing.sh \
  scripts/test_diagnose_release_signing.sh \
  scripts/record_release_smoke_result.sh \
  scripts/test_record_release_smoke_result.sh \
  scripts/manual_smoke_readiness.sh \
  scripts/test_manual_smoke_readiness.sh \
  scripts/check_release_completion.sh \
  scripts/test_check_release_completion.sh \
  scripts/test_privacy_manifest.sh \
  scripts/test_privacy_surface.sh \
  scripts/test_required_reason_api_scan.sh \
  scripts/run_release_candidate_gate.sh \
  scripts/test_run_release_candidate_gate.sh \
  scripts/test_verify_release_readiness.sh \
  scripts/verify_release_readiness.sh

run scripts/test_collect_release_candidate_evidence.sh
run scripts/test_diagnose_release_signing.sh
run scripts/test_record_release_smoke_result.sh
run "$MANUAL_SMOKE_READINESS_TEST_SCRIPT"
run "$CHECK_RELEASE_COMPLETION_TEST_SCRIPT"
run "$PRIVACY_MANIFEST_TEST_SCRIPT"
run "$PRIVACY_SURFACE_TEST_SCRIPT"
run "$REQUIRED_REASON_API_SCAN_SCRIPT"
run "$RUN_LIVE_DEEPSEEK_TRANSLATION_SMOKE_TEST_SCRIPT"
run "$RUN_CANDIDATE_GATE_TEST_SCRIPT"
if [[ "${WORDSCENE_SKIP_READINESS_SELF_TEST:-0}" != "1" ]]; then
  run scripts/test_verify_release_readiness.sh
fi
run git diff --check

expect_no_matches \
  "DeepSeek token is absent from tracked project surfaces" \
  rg -n "$TOKEN_SCAN_PATTERN" WordScene docs project.yml .gitignore scripts

expect_no_matches \
  "XcodeGen did not restore old Xcode upgrade markers" \
  rg -n 'LastUpgradeCheck = 1430|LastUpgradeVersion = "1430"' \
    WordScene.xcodeproj/project.pbxproj \
    WordScene.xcodeproj/xcshareddata/xcschemes/WordScene.xcscheme \
    WordScene.xcodeproj/xcshareddata/xcschemes/WordSceneMac.xcscheme

run xcodebuild test \
  -project WordScene.xcodeproj \
  -scheme WordSceneMac \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WordSceneVerifyMac \
  CODE_SIGNING_ALLOWED=NO

run xcodebuild build \
  -project WordScene.xcodeproj \
  -scheme WordScene \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/WordSceneVerifyIOS \
  CODE_SIGNING_ALLOWED=NO

run xcodebuild build \
  -project WordScene.xcodeproj \
  -scheme WordSceneMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/WordSceneVerifyReleaseMac \
  CODE_SIGNING_ALLOWED=NO

run xcodebuild build \
  -project WordScene.xcodeproj \
  -scheme WordScene \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/WordSceneVerifyReleaseIOS \
  CODE_SIGNING_ALLOWED=NO

printf '\nRelease readiness checks passed for non-manual gates.\n'
