#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
  scripts/test_verify_release_readiness.sh \
  scripts/verify_release_readiness.sh

run scripts/test_collect_release_candidate_evidence.sh
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

printf '\nRelease readiness checks passed for non-manual gates.\n'
