#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="macos"
DESTINATION="platform=macOS"
DRY_RUN=0
PRINT_SCHEMA=0

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/initialize_cloudkit_schema.sh [--platform macos|ios] [--device <identifier>] [--dry-run] [--print-schema]

Initializes the CloudKit development schema through a signed test host.
Use this only for development schema setup, not as an App Store production step.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      PLATFORM="$2"
      shift 2
      ;;
    --device)
      if [[ $# -lt 2 ]]; then
        usage
        exit 64
      fi
      DESTINATION="id=$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --print-schema)
      PRINT_SCHEMA=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

case "$PLATFORM" in
  macos)
    SCHEME="WordSceneMac"
    TEST_IDENTIFIER="WordSceneMacTests/CloudKitSchemaInitializationTests/testInitializeCloudKitDevelopmentSchema"
    ;;
  ios)
    SCHEME="WordScene"
    TEST_IDENTIFIER="WordSceneTests/CloudKitSchemaInitializationTests/testInitializeCloudKitDevelopmentSchema"
    if [[ "$DESTINATION" == "platform=macOS" ]]; then
      echo "iOS schema initialization requires --device <identifier> for a signed physical device." >&2
      exit 64
    fi
    ;;
  *)
    usage
    exit 64
    ;;
esac

WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA=1 \
WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_DRY_RUN="$DRY_RUN" \
WORDSCENE_INITIALIZE_CLOUDKIT_SCHEMA_PRINT="$PRINT_SCHEMA" \
xcodebuild test \
  -project "$ROOT/WordScene.xcodeproj" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -only-testing:"$TEST_IDENTIFIER"
