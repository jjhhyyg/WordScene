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

chmod +x "$BIN/git" "$BIN/rg" "$BIN/xcodebuild"

PATH="$BIN:$PATH" \
  WORDSCENE_FAKE_COMMAND_LOG="$LOG" \
  WORDSCENE_SKIP_READINESS_SELF_TEST=1 \
  "$ROOT/scripts/verify_release_readiness.sh"

grep -qF 'git diff --check' "$LOG"
token_pattern='sk-[A-Za-z0-9]|e2a'
token_pattern+='988'
grep -qF "rg -n $token_pattern WordScene docs project.yml .gitignore scripts" "$LOG"
grep -qF 'rg -n LastUpgradeCheck = 1430|LastUpgradeVersion = "1430" WordScene.xcodeproj/project.pbxproj WordScene.xcodeproj/xcshareddata/xcschemes/WordScene.xcscheme WordScene.xcodeproj/xcshareddata/xcschemes/WordSceneMac.xcscheme' "$LOG"
grep -qF "xcodebuild test -project WordScene.xcodeproj -scheme WordSceneMac -destination platform=macOS -derivedDataPath /tmp/WordSceneVerifyMac CODE_SIGNING_ALLOWED=NO" "$LOG"
grep -qF "xcodebuild build -project WordScene.xcodeproj -scheme WordScene -destination generic/platform=iOS -derivedDataPath /tmp/WordSceneVerifyIOS CODE_SIGNING_ALLOWED=NO" "$LOG"
