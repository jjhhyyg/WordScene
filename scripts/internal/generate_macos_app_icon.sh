#!/bin/zsh
set -euo pipefail

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "TARGET_BUILD_DIR and UNLOCALIZED_RESOURCES_FOLDER_PATH must be set by Xcode." >&2
  exit 1
fi

SOURCE_ICON_SET="${SRCROOT}/WordScene/Resources/Assets.xcassets/AppIcon.appiconset"
OUTPUT_ICON="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/AppIcon.icns"
WORK_DIR="${DERIVED_FILE_DIR}/WordSceneMacAppIcon.iconset"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

cp "${SOURCE_ICON_SET}/Icon-16-mac.png" "${WORK_DIR}/icon_16x16.png"
cp "${SOURCE_ICON_SET}/Icon-16-mac@2x.png" "${WORK_DIR}/icon_16x16@2x.png"
cp "${SOURCE_ICON_SET}/Icon-32-mac.png" "${WORK_DIR}/icon_32x32.png"
cp "${SOURCE_ICON_SET}/Icon-32-mac@2x.png" "${WORK_DIR}/icon_32x32@2x.png"
cp "${SOURCE_ICON_SET}/Icon-128-mac.png" "${WORK_DIR}/icon_128x128.png"
cp "${SOURCE_ICON_SET}/Icon-128-mac@2x.png" "${WORK_DIR}/icon_128x128@2x.png"
cp "${SOURCE_ICON_SET}/Icon-256-mac.png" "${WORK_DIR}/icon_256x256.png"
cp "${SOURCE_ICON_SET}/Icon-256-mac@2x.png" "${WORK_DIR}/icon_256x256@2x.png"
cp "${SOURCE_ICON_SET}/Icon-512-mac.png" "${WORK_DIR}/icon_512x512.png"
cp "${SOURCE_ICON_SET}/Icon-1024.png" "${WORK_DIR}/icon_512x512@2x.png"

iconutil -c icns "${WORK_DIR}" -o "${OUTPUT_ICON}"
