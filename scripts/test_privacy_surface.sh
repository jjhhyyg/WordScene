#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS_VIEW="$ROOT/WordScene/Sources/Shared/Features/Settings/SettingsView.swift"

if rg -n 'allowsAnonymousCrashReports|匿名崩溃日志' "$SETTINGS_VIEW" >/tmp/wordscene-privacy-surface.out; then
  echo "Settings exposes anonymous crash reporting controls without an implemented crash reporting service." >&2
  cat /tmp/wordscene-privacy-surface.out >&2
  exit 1
fi
