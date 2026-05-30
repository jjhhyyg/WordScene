#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

APP_PATH="$TMPDIR/Word Scene.app"
DEVICE_LIST="$TMPDIR/devices.txt"
mkdir -p "$APP_PATH"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   available     iPhone 17 Pro Max
Lab iPad         Lab-iPad.coredevice.local        00000000-0000-0000-0000-000000000002   unavailable   iPad Pro 11-inch
DEVICES

"$ROOT/scripts/install_ios_release_candidate.sh" \
  --app "$APP_PATH" \
  --device-list "$DEVICE_LIST" \
  --timeout 15 \
  --dry-run >"$TMPDIR/dry-run.out"

grep -qF 'DRY RUN: xcrun devicectl device install app --device' "$TMPDIR/dry-run.out"
grep -qF '00000000-0000-0000-0000-000000000001' "$TMPDIR/dry-run.out"
grep -qF 'Word\ Scene.app' "$TMPDIR/dry-run.out"

"$ROOT/scripts/install_ios_release_candidate.sh" \
  --app "$APP_PATH" \
  --device 'Moses-iPhone.coredevice.local' \
  --timeout 15 \
  --dry-run >"$TMPDIR/explicit-device.out"

grep -qF 'Moses-iPhone.coredevice.local' "$TMPDIR/explicit-device.out"

cat >"$DEVICE_LIST" <<'DEVICES'
Name             Hostname                         Identifier                             State         Model
--------------   ------------------------------   ------------------------------------   -----------   --------------------
Moses iPhone     Moses-iPhone.coredevice.local    00000000-0000-0000-0000-000000000001   unavailable   iPhone 17 Pro Max
DEVICES

if "$ROOT/scripts/install_ios_release_candidate.sh" \
  --app "$APP_PATH" \
  --device-list "$DEVICE_LIST" \
  --dry-run >"$TMPDIR/no-device.out" 2>"$TMPDIR/no-device.err"; then
  echo "Expected unavailable devices to fail." >&2
  exit 1
fi

grep -qF 'No available physical iPhone or iPad was reported by devicectl.' "$TMPDIR/no-device.err"

if "$ROOT/scripts/install_ios_release_candidate.sh" \
  --app "$APP_PATH" \
  --device '00000000-0000-0000-0000-000000000001' \
  --device-list "$DEVICE_LIST" \
  --dry-run >"$TMPDIR/unavailable-explicit.out" 2>"$TMPDIR/unavailable-explicit.err"; then
  echo "Expected an explicitly selected unavailable device to fail before install." >&2
  exit 1
fi

grep -qF 'Selected iPhone/iPad is visible but unavailable: 00000000-0000-0000-0000-000000000001' "$TMPDIR/unavailable-explicit.err"
grep -qF 'Unlock it, trust this Mac, confirm Developer Mode, and reconnect or re-pair it before installing.' "$TMPDIR/unavailable-explicit.err"

if "$ROOT/scripts/install_ios_release_candidate.sh" \
  --app "$TMPDIR/Missing.app" \
  --device-list "$DEVICE_LIST" \
  --dry-run >"$TMPDIR/missing-app.out" 2>"$TMPDIR/missing-app.err"; then
  echo "Expected missing candidate app to fail." >&2
  exit 1
fi

grep -qF 'iOS release candidate app not found:' "$TMPDIR/missing-app.err"
