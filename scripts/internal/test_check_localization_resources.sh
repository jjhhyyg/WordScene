#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/internal/check_localization_resources.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wordscene-localization-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

make_fixture() {
  local resources="$1"
  mkdir -p "$resources/zh-Hans.lproj" "$resources/en.lproj" "$resources/es.lproj"
  cat >"$resources/Localizable.xcstrings" <<'JSON'
{
  "sourceLanguage": "zh-Hans",
  "strings": {
    "%@": {},
    "设置": {
      "localizations": {
        "zh-Hans": {
          "stringUnit": {
            "state": "translated",
            "value": "设置"
          }
        },
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "Settings"
          }
        },
        "es": {
          "stringUnit": {
            "state": "translated",
            "value": "Ajustes"
          }
        }
      }
    },
    "%lld 个结果": {
      "localizations": {
        "zh-Hans": {
          "variations": {
            "plural": {
              "one": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld 个结果"
                }
              },
              "other": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld 个结果"
                }
              }
            }
          }
        },
        "en": {
          "variations": {
            "plural": {
              "one": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld result"
                }
              },
              "other": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld results"
                }
              }
            }
          }
        },
        "es": {
          "variations": {
            "plural": {
              "one": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld resultado"
                }
              },
              "other": {
                "stringUnit": {
                  "state": "translated",
                  "value": "%lld resultados"
                }
              }
            }
          }
        }
      }
    }
  },
  "version": "1.0"
}
JSON

  cat >"$resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "译笺";
CFBundleName = "Word Scene";
STRINGS
  cat >"$resources/en.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "Word Scene";
CFBundleName = "Word Scene";
STRINGS
  cat >"$resources/es.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "Escena de Palabras";
CFBundleName = "Word Scene";
STRINGS
}

expect_failure() {
  local description="$1"
  local expected="$2"
  shift 2

  set +e
  "$@" >"$TMP_DIR/out.txt" 2>"$TMP_DIR/err.txt"
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "Expected failure: $description" >&2
    exit 1
  fi
  if ! grep -qF "$expected" "$TMP_DIR/err.txt"; then
    echo "Failure for '$description' did not mention expected text: $expected" >&2
    cat "$TMP_DIR/err.txt" >&2
    exit 1
  fi
}

PASSING_RESOURCES="$TMP_DIR/passing"
make_fixture "$PASSING_RESOURCES"
"$SCRIPT" "$PASSING_RESOURCES" >/tmp/wordscene-localization-pass.out
grep -qF "Localization resources are complete for zh-Hans, en, es." /tmp/wordscene-localization-pass.out

MISSING_CATALOG_LANGUAGE="$TMP_DIR/missing-catalog-language"
make_fixture "$MISSING_CATALOG_LANGUAGE"
/usr/bin/python3 - "$MISSING_CATALOG_LANGUAGE/Localizable.xcstrings" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    catalog = json.load(handle)
del catalog["strings"]["设置"]["localizations"]["es"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(catalog, handle, ensure_ascii=False, indent=2)
PY
expect_failure \
  "missing string catalog language" \
  "Missing es localization for Localizable.xcstrings key: 设置" \
  "$SCRIPT" "$MISSING_CATALOG_LANGUAGE"

MISSING_INFO_KEY="$TMP_DIR/missing-info-key"
make_fixture "$MISSING_INFO_KEY"
cat >"$MISSING_INFO_KEY/en.lproj/InfoPlist.strings" <<'STRINGS'
CFBundleDisplayName = "Word Scene";
STRINGS
expect_failure \
  "missing InfoPlist key" \
  "Missing CFBundleName in en.lproj/InfoPlist.strings" \
  "$SCRIPT" "$MISSING_INFO_KEY"
