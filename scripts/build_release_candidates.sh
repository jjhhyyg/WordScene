#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_BASE="${DERIVED_DATA_BASE:-/tmp/WordSceneReleaseCandidates}"
EXTRA_XCODEBUILD_FLAGS=()
PLATFORM="all"

usage() {
  echo "Usage: $0 [--allow-provisioning-updates] [--platform all|macos|ios]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-provisioning-updates)
      EXTRA_XCODEBUILD_FLAGS+=("-allowProvisioningUpdates")
      shift
      ;;
    --platform)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PLATFORM="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

case "$PLATFORM" in
  all|macos|ios) ;;
  *)
    echo "Unsupported platform '$PLATFORM'. Expected all, macos, or ios." >&2
    exit 64
    ;;
esac

build_macos() {
  xcodebuild build \
    -project "$ROOT/WordScene.xcodeproj" \
    -scheme WordSceneMac \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_BASE/macOS" \
    "${EXTRA_XCODEBUILD_FLAGS[@]}"
}

build_ios() {
  xcodebuild build \
    -project "$ROOT/WordScene.xcodeproj" \
    -scheme WordScene \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA_BASE/iOS" \
    "${EXTRA_XCODEBUILD_FLAGS[@]}"
}

case "$PLATFORM" in
  all)
    build_macos
    build_ios
    ;;
  macos)
    build_macos
    ;;
  ios)
    build_ios
    ;;
esac
