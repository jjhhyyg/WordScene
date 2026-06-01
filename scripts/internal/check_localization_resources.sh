#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOURCES_DIR="${1:-$ROOT/WordScene/Resources}"
CATALOG="$RESOURCES_DIR/Localizable.xcstrings"
SUPPORTED_LANGUAGES=(
  "zh-Hans"
  "zh-Hant"
  "en"
  "es"
  "fr"
  "de"
  "pt"
  "it"
  "ru"
  "ja"
  "ko"
  "nl"
  "pl"
  "ar"
  "tr"
  "vi"
  "id"
  "hi"
)
REQUIRED_INFO_PLIST_KEYS=("CFBundleDisplayName" "CFBundleName")

if [[ ! -d "$RESOURCES_DIR" ]]; then
  echo "Localization resources directory not found: $RESOURCES_DIR" >&2
  exit 1
fi

if [[ ! -f "$CATALOG" ]]; then
  echo "Missing Localizable.xcstrings at: $CATALOG" >&2
  exit 1
fi

/usr/bin/python3 - "$CATALOG" "${SUPPORTED_LANGUAGES[@]}" <<'PY'
import json
import sys

catalog_path = sys.argv[1]
languages = sys.argv[2:]
allowed_unlocalized_keys = {"%@"}

with open(catalog_path, encoding="utf-8") as handle:
    catalog = json.load(handle)

source_language = catalog.get("sourceLanguage")
if source_language != "zh-Hans":
    print(f"Localizable.xcstrings sourceLanguage should be zh-Hans, found: {source_language}", file=sys.stderr)
    sys.exit(1)

strings = catalog.get("strings")
if not isinstance(strings, dict) or not strings:
    print("Localizable.xcstrings has no strings dictionary.", file=sys.stderr)
    sys.exit(1)


def collect_values(localization):
    values = []
    string_unit = localization.get("stringUnit")
    if isinstance(string_unit, dict):
        values.append(string_unit.get("value"))

    variations = localization.get("variations")
    if isinstance(variations, dict):
        plural = variations.get("plural")
        if isinstance(plural, dict):
            for variation in plural.values():
                if isinstance(variation, dict):
                    unit = variation.get("stringUnit")
                    if isinstance(unit, dict):
                        values.append(unit.get("value"))
    return values


for key, entry in sorted(strings.items()):
    if not isinstance(entry, dict):
        print(f"Invalid Localizable.xcstrings entry for key: {key}", file=sys.stderr)
        sys.exit(1)

    localizations = entry.get("localizations")
    if localizations is None:
        if key in allowed_unlocalized_keys:
            continue
        print(f"Missing localizations for Localizable.xcstrings key: {key}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(localizations, dict):
        print(f"Invalid localizations object for Localizable.xcstrings key: {key}", file=sys.stderr)
        sys.exit(1)

    for language in languages:
        localization = localizations.get(language)
        if localization is None:
            print(f"Missing {language} localization for Localizable.xcstrings key: {key}", file=sys.stderr)
            sys.exit(1)
        if not isinstance(localization, dict):
            print(f"Invalid {language} localization for Localizable.xcstrings key: {key}", file=sys.stderr)
            sys.exit(1)

        values = collect_values(localization)
        if not values:
            print(f"Missing {language} translated value for Localizable.xcstrings key: {key}", file=sys.stderr)
            sys.exit(1)
        for value in values:
            if not isinstance(value, str) or not value.strip():
                print(f"Blank {language} translated value for Localizable.xcstrings key: {key}", file=sys.stderr)
                sys.exit(1)
PY

for language in "${SUPPORTED_LANGUAGES[@]}"; do
  info_plist="$RESOURCES_DIR/$language.lproj/InfoPlist.strings"
  if [[ ! -f "$info_plist" ]]; then
    echo "Missing $language.lproj/InfoPlist.strings" >&2
    exit 1
  fi

  plutil -lint "$info_plist" >/tmp/wordscene-localization-infoplist-lint.out

  for key in "${REQUIRED_INFO_PLIST_KEYS[@]}"; do
    if ! value="$(plutil -extract "$key" raw -o - "$info_plist" 2>/tmp/wordscene-localization-infoplist-extract.err)"; then
      echo "Missing $key in $language.lproj/InfoPlist.strings" >&2
      exit 1
    fi
    if [[ -z "${value//[[:space:]]/}" ]]; then
      echo "Blank $key in $language.lproj/InfoPlist.strings" >&2
      exit 1
    fi
  done
done

echo "Localization resources are complete for ${SUPPORTED_LANGUAGES[*]}."
