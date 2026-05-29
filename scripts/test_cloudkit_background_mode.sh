#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! rg -n 'INFOPLIST_KEY_UIBackgroundModes:[[:space:]]+remote-notification' "$ROOT/project.yml" >/tmp/wordscene-cloudkit-background-project.out; then
  echo "iOS target uses CloudKit but project.yml does not declare remote-notification background mode." >&2
  exit 1
fi

if ! rg -n 'INFOPLIST_KEY_UIBackgroundModes = "remote-notification";' "$ROOT/WordScene.xcodeproj/project.pbxproj" >/tmp/wordscene-cloudkit-background-pbxproj.out; then
  echo "iOS target uses CloudKit but the generated Xcode project does not declare remote-notification background mode." >&2
  exit 1
fi
