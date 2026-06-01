#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_FILE="$ROOT/.local/deepseek-token"
BASE_URL="https://api.deepseek.com"
MODEL="deepseek-v4-flash"
SOURCE_LANGUAGE="Auto-detect"
TARGET_LANGUAGE="Chinese"
TEXT="hello world"
EVIDENCE_FILE=""

usage() {
  echo "Usage: $0 [--token-file <path>] [--base-url <url>] [--model <name>] [--source <name>] [--target <name>] [--text <text>] [--evidence <markdown>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token-file)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      TOKEN_FILE="$2"
      shift 2
      ;;
    --base-url)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      BASE_URL="${2%/}"
      shift 2
      ;;
    --model)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      MODEL="$2"
      shift 2
      ;;
    --source)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      SOURCE_LANGUAGE="$2"
      shift 2
      ;;
    --target)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      TARGET_LANGUAGE="$2"
      shift 2
      ;;
    --text)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      TEXT="$2"
      shift 2
      ;;
    --evidence)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      EVIDENCE_FILE="$2"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "DeepSeek token file not found: $TOKEN_FILE" >&2
  exit 66
fi

worktree_status() {
  if [[ -n "${WORDSCENE_LIVE_SMOKE_WORKTREE_STATUS+x}" ]]; then
    printf '%s\n' "$WORDSCENE_LIVE_SMOKE_WORKTREE_STATUS"
    return
  fi

  git -C "$ROOT" status --porcelain --untracked-files=normal
}

assert_clean_worktree_for_evidence() {
  local status

  if [[ -z "$EVIDENCE_FILE" ]]; then
    return
  fi

  status="$(worktree_status)"
  if [[ -n "$status" ]]; then
    echo "DeepSeek live smoke evidence requires a clean git worktree. Commit or stash changes before recording evidence." >&2
    exit 1
  fi
}

assert_clean_worktree_for_evidence

TOKEN="$(tr -d '\r\n[:space:]' <"$TOKEN_FILE")"
if [[ -z "$TOKEN" ]]; then
  echo "DeepSeek token file is empty: $TOKEN_FILE" >&2
  exit 65
fi

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT
chmod 700 "$TMPDIR"

CURL_CONFIG="$TMPDIR/curl.conf"
REQUEST_BODY="$TMPDIR/request.json"
RESPONSE_BODY="$TMPDIR/response.json"
TRANSLATED_TEXT_FILE="$TMPDIR/translated.txt"

umask 077
cat >"$CURL_CONFIG" <<EOF
silent
show-error
fail-with-body
request = "POST"
url = "$BASE_URL/chat/completions"
header = "Authorization: Bearer $TOKEN"
header = "Content-Type: application/json"
header = "Accept: application/json"
EOF

/usr/bin/python3 - "$REQUEST_BODY" "$MODEL" "$SOURCE_LANGUAGE" "$TARGET_LANGUAGE" "$TEXT" <<'PY'
import json
import sys

request_path, model, source_language, target_language, text = sys.argv[1:]
prompt_input = {
    "source_language": source_language,
    "target_language": target_language,
    "text": text,
}
user_prompt = "\n".join(
    [
        "Translate only the text field in the input json object below.",
        'Return json matching {"translated_text":"..."}.',
        "Input json:",
        json.dumps(prompt_input, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
    ]
)
body = {
    "model": model,
    "messages": [
        {
            "role": "system",
            "content": 'You are a precise translation engine for a language learning app. Return json only. Use exactly this schema: {"translated_text":"..."}. Do not add explanations, alternatives, markdown, or notes.',
        },
        {"role": "user", "content": user_prompt},
    ],
    "thinking": {"type": "disabled"},
    "response_format": {"type": "json_object"},
    "max_tokens": 1200,
    "temperature": 0.2,
    "stream": False,
}
with open(request_path, "w", encoding="utf-8") as handle:
    json.dump(body, handle, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
PY

curl --config "$CURL_CONFIG" --data-binary "@$REQUEST_BODY" >"$RESPONSE_BODY"

/usr/bin/python3 - "$RESPONSE_BODY" "$SOURCE_LANGUAGE" "$TARGET_LANGUAGE" "$TRANSLATED_TEXT_FILE" <<'PY'
import json
import sys

response_path, source_language, target_language, translated_text_path = sys.argv[1:]
with open(response_path, "r", encoding="utf-8") as handle:
    response = json.load(handle)

choices = response.get("choices") or []
if not choices:
    raise SystemExit("DeepSeek response did not include choices.")

choice = choices[0]
finish_reason = choice.get("finish_reason")
if finish_reason == "length":
    raise SystemExit("DeepSeek output was truncated.")
if finish_reason == "content_filter":
    raise SystemExit("DeepSeek filtered the content.")
if finish_reason == "insufficient_system_resource":
    raise SystemExit("DeepSeek reported insufficient system resources.")
if finish_reason not in (None, "stop"):
    raise SystemExit(f"Unexpected DeepSeek finish_reason: {finish_reason}")

message = choice.get("message") or {}
content = (message.get("content") or "").strip()
if not content:
    raise SystemExit("DeepSeek returned empty assistant content.")

try:
    parsed_content = json.loads(content)
except json.JSONDecodeError as error:
    raise SystemExit(f"DeepSeek assistant content was not JSON: {error}") from error

translated_text = (parsed_content.get("translated_text") or "").strip()
if not translated_text:
    raise SystemExit("DeepSeek assistant JSON did not include translated_text.")

with open(translated_text_path, "w", encoding="utf-8") as handle:
    handle.write(translated_text)

print("PASS: DeepSeek live translation smoke returned translated text.")
print(f"Source language: {source_language}")
print(f"Target language: {target_language}")
print(f"Translated: {translated_text}")
PY

markdown_cell() {
  tr '\n' ' ' |
    sed 's/|/\\|/g; s/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

record_evidence() {
  local evidence_file="$1"
  local translated_text="$2"
  local timestamp
  local git_commit
  local escaped_translation
  local notes
  local row
  local temp_file
  local preserved_rows
  local preserved_rest

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  git_commit="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
  escaped_translation="$(printf '%s' "$translated_text" | markdown_cell)"
  notes="\`scripts/run_live_deepseek_translation_smoke.sh\` passed at $timestamp using the ignored local token file. Git commit \`$git_commit\`. It verified JSON Output with the real DeepSeek API and returned \`$escaped_translation\` without printing the token."
  row="| DeepSeek live protocol smoke | API | local build host | 1 | PASS | $notes |"

  mkdir -p "$(dirname "$evidence_file")"
  temp_file="$(mktemp)"
  preserved_rows="$(mktemp)"
  preserved_rest="$(mktemp)"

  if [[ -f "$evidence_file" ]]; then
    awk '
      /^## Non-Manual Release Gate$/ {
        in_section = 1
        next
      }
      in_section == 1 && /^## / {
        in_section = 0
      }
      in_section == 1 &&
      /^\| / &&
      $0 !~ /^\| Area \|/ &&
      $0 !~ /^\| ---/ &&
      $0 !~ /^\| DeepSeek live protocol smoke \|/ {
        print
      }
    ' "$evidence_file" >"$preserved_rows"

    awk '
      /^## Non-Manual Release Gate$/ {
        skip = 1
        next
      }
      /^## / {
        skip = 0
      }
      skip != 1 {
        print
      }
    ' "$evidence_file" >"$preserved_rest"
  fi

  {
    printf '## Non-Manual Release Gate\n\n'
    printf '| Area | Platform | Device / OS | Build | Result | Notes |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    cat "$preserved_rows"
    printf '%s\n' "$row"
    if [[ -s "$preserved_rest" ]]; then
      printf '\n'
      cat "$preserved_rest"
    fi
  } >"$temp_file"

  mv "$temp_file" "$evidence_file"
  rm -f "$preserved_rows" "$preserved_rest"
}

if [[ -n "$EVIDENCE_FILE" ]]; then
  record_evidence "$EVIDENCE_FILE" "$(cat "$TRANSLATED_TEXT_FILE")"
fi
