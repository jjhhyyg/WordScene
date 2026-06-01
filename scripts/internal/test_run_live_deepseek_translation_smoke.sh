#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

BIN="$TMPDIR/bin"
TOKEN_FILE="$TMPDIR/deepseek-token"
LOG="$TMPDIR/curl.log"
DIRTY_LOG="$TMPDIR/dirty-curl.log"
EVIDENCE="$TMPDIR/release-smoke-evidence.md"
DIRTY_EVIDENCE="$TMPDIR/dirty-release-smoke-evidence.md"
ORIGINAL_DIRTY_EVIDENCE="$TMPDIR/original-dirty-release-smoke-evidence.md"
mkdir -p "$BIN"
printf 'test-token-secret\n' >"$TOKEN_FILE"
cat >"$EVIDENCE" <<'MARKDOWN'
## Non-Manual Release Gate

| Area | Platform | Device / OS | Build | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| Readiness script | macOS + iOS generic | local build host | 1 | PASS | PRESERVED READINESS |
| DeepSeek live protocol smoke | API | local build host | 1 | PASS | STALE LIVE ROW |

## Release Candidate Build Evidence

PRESERVED CANDIDATE EVIDENCE
MARKDOWN
cp "$EVIDENCE" "$DIRTY_EVIDENCE"
cp "$DIRTY_EVIDENCE" "$ORIGINAL_DIRTY_EVIDENCE"

cat >"$BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -euo pipefail

printf 'curl %s\n' "$*" >>"$WORDSCENE_FAKE_CURL_LOG"
case "$*" in
  *test-token-secret*)
    echo "token leaked into curl argv" >&2
    exit 70
    ;;
esac

config=""
body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      config="$2"
      shift 2
      ;;
    --data-binary)
      body="${2#@}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

grep -qF 'Authorization: Bearer test-token-secret' "$config"
grep -qF 'Accept: text/event-stream' "$config"
grep -qF 'max-time = 10' "$config"
grep -qF '"model":"deepseek-v4-flash"' "$body"
grep -qF '"response_format":{"type":"json_object"}' "$body"
grep -qF '"thinking":{"type":"disabled"}' "$body"
grep -qF '"stream":true' "$body"
grep -qF 'translated_text' "$body"
grep -qF '\"source_language\":\"Auto-detect\"' "$body"
grep -qF '\"target_language\":\"Chinese\"' "$body"
grep -qF '\"text\":\"hello world\"' "$body"

cat <<'SSE'
data: {"choices":[{"index":0,"finish_reason":null,"delta":{"content":"{\"translated_text\":\"你好，世界。\"}"}}]}

data: [DONE]

SSE
FAKE_CURL

chmod +x "$BIN/curl"

OUTPUT="$(
  PATH="$BIN:$PATH" \
    WORDSCENE_FAKE_CURL_LOG="$LOG" \
    WORDSCENE_LIVE_SMOKE_WORKTREE_STATUS="" \
    "$ROOT/scripts/run_live_deepseek_translation_smoke.sh" \
      --token-file "$TOKEN_FILE" \
      --text "hello world" \
      --evidence "$EVIDENCE"
)"

grep -qF 'PASS: DeepSeek live translation smoke returned translated text.' <<<"$OUTPUT"
grep -qF 'Translated: 你好，世界。' <<<"$OUTPUT"
! grep -qF 'test-token-secret' "$LOG"
! grep -qF 'test-token-secret' "$EVIDENCE"
grep -qF '| Readiness script | macOS + iOS generic | local build host | 1 | PASS | PRESERVED READINESS |' "$EVIDENCE"
grep -qF '| DeepSeek live protocol smoke | API | local build host | 1 | PASS | `scripts/run_live_deepseek_translation_smoke.sh` passed at ' "$EVIDENCE"
grep -qF "Git commit \`$(git -C "$ROOT" rev-parse --short=12 HEAD)\`." "$EVIDENCE"
grep -qF 'It verified JSON Output with the real DeepSeek API and returned `你好，世界。` without printing the token.' "$EVIDENCE"
grep -qF 'PRESERVED CANDIDATE EVIDENCE' "$EVIDENCE"
if grep -qF 'STALE LIVE ROW' "$EVIDENCE"; then
  echo "stale live evidence row was not replaced" >&2
  exit 1
fi

set +e
PATH="$BIN:$PATH" \
  WORDSCENE_FAKE_CURL_LOG="$DIRTY_LOG" \
  WORDSCENE_LIVE_SMOKE_WORKTREE_STATUS=' M WordScene/Sources/Shared/Features/Translate/TranslationView.swift' \
  "$ROOT/scripts/run_live_deepseek_translation_smoke.sh" \
    --token-file "$TOKEN_FILE" \
    --text "hello world" \
    --evidence "$DIRTY_EVIDENCE" >"$TMPDIR/dirty.out" 2>"$TMPDIR/dirty.err"
status=$?
set -e

test "$status" -eq 1
grep -qF 'DeepSeek live smoke evidence requires a clean git worktree.' "$TMPDIR/dirty.err"
! test -s "$DIRTY_LOG"
cmp "$ORIGINAL_DIRTY_EVIDENCE" "$DIRTY_EVIDENCE" >/dev/null
