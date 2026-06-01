#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETTINGS_VIEW="$ROOT/WordScene/Sources/Shared/Features/Settings/SettingsView.swift"
DOCS=(
  "$ROOT/docs/project-config.md"
  "$ROOT/docs/v2-design.md"
)

if rg -n 'allowsAnonymousCrashReports|匿名崩溃日志' "$SETTINGS_VIEW" >/tmp/wordscene-privacy-surface.out; then
  echo "Settings exposes anonymous crash reporting controls without an implemented crash reporting service." >&2
  cat /tmp/wordscene-privacy-surface.out >&2
  exit 1
fi

if rg -n '崩溃日志默认|崩溃日志设置|匿名崩溃日志设置|保存用户是否允许匿名崩溃日志上传|Release build 保留匿名崩溃日志|预留用户选择接口|匿名崩溃日志用户选择接口预留' "${DOCS[@]}" >/tmp/wordscene-privacy-docs.out; then
  echo "Docs still describe crash-reporting controls that the product does not implement." >&2
  cat /tmp/wordscene-privacy-docs.out >&2
  exit 1
fi
