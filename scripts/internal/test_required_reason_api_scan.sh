#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/WordScene/Resources/PrivacyInfo.xcprivacy"
SOURCE_DIR="$ROOT/WordScene/Sources"

manifest_has_reason() {
  local api_type="$1"
  local reason="$2"

  for index in $(seq 0 20); do
    local current_type
    current_type="$(plutil -extract "NSPrivacyAccessedAPITypes.$index.NSPrivacyAccessedAPIType" raw -o - "$MANIFEST" 2>/dev/null || true)"
    [[ -n "$current_type" ]] || break

    if [[ "$current_type" == "$api_type" ]] &&
      /usr/libexec/PlistBuddy -c "Print :NSPrivacyAccessedAPITypes:$index:NSPrivacyAccessedAPITypeReasons" "$MANIFEST" 2>/dev/null |
        grep -qF "$reason"; then
      return 0
    fi
  done

  return 1
}

if rg -n '\bUserDefaults\b|@AppStorage\b' "$SOURCE_DIR" >/tmp/wordscene-required-reason-userdefaults.out; then
  if ! manifest_has_reason "NSPrivacyAccessedAPICategoryUserDefaults" "CA92.1"; then
    echo "Production code uses UserDefaults/AppStorage but PrivacyInfo.xcprivacy does not declare UserDefaults reason CA92.1." >&2
    cat /tmp/wordscene-required-reason-userdefaults.out >&2
    exit 1
  fi
fi

if rg -n 'attributesOfItem|attributesOfFileSystem|contentModificationDateKey|creationDateKey|fileModificationDate|resourceValues\(' "$SOURCE_DIR" >/tmp/wordscene-required-reason-filetimestamp.out; then
  echo "Production code appears to use file timestamp or file-system metadata APIs. Classify the required reason and update PrivacyInfo.xcprivacy before release." >&2
  cat /tmp/wordscene-required-reason-filetimestamp.out >&2
  exit 1
fi

if rg -n 'volumeAvailableCapacity|volumeAvailableCapacityForImportantUsage|volumeAvailableCapacityForOpportunisticUsage|systemFreeSize|systemSize' "$SOURCE_DIR" >/tmp/wordscene-required-reason-storage-capacity.out; then
  echo "Production code appears to use storage-capacity APIs. Classify the required reason and update PrivacyInfo.xcprivacy before release." >&2
  cat /tmp/wordscene-required-reason-storage-capacity.out >&2
  exit 1
fi

if rg -n 'systemUptime|mach_absolute_time|mach_continuous_time' "$SOURCE_DIR" >/tmp/wordscene-required-reason-boot-time.out; then
  echo "Production code appears to use system boot-time APIs. Classify the required reason and update PrivacyInfo.xcprivacy before release." >&2
  cat /tmp/wordscene-required-reason-boot-time.out >&2
  exit 1
fi

if rg -n 'activeInputModes' "$SOURCE_DIR" >/tmp/wordscene-required-reason-keyboard.out; then
  echo "Production code appears to use active keyboard APIs. Classify the required reason and update PrivacyInfo.xcprivacy before release." >&2
  cat /tmp/wordscene-required-reason-keyboard.out >&2
  exit 1
fi
