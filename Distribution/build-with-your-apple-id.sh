#!/usr/bin/env bash
# Build and install EV Info on a connected iPhone using the Mac owner's Apple ID.
# Works with a free (personal team) Apple ID; the signature lasts 7 days.
#
# Usage:
#   ./build-with-your-apple-id.sh [TEAM_ID] [DEVICE_UDID]
#
# Before running: Xcode > Settings > Accounts > add the Apple ID, and enable
# Developer Mode on the iPhone (Settings > Privacy & Security > Developer Mode).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${1:-${TEAM_ID:-}}"
DEVICE="${2:-${DEVICE_UDID:-}}"

if [ -z "$TEAM" ]; then
  TEAM="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1)"
fi
if [ -z "$TEAM" ]; then
  echo "error: no code-signing identity found." >&2
  echo "Open Xcode > Settings > Accounts, sign in with your Apple ID, then retry." >&2
  exit 1
fi

if [ -z "$DEVICE" ]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ && /physical/ {print $2; exit}')"
fi
if [ -z "$DEVICE" ]; then
  echo "error: no connected iPhone found. Plug it in, unlock it and trust this Mac." >&2
  exit 1
fi

echo "==> Team:   $TEAM"
echo "==> Device: $DEVICE"

xcodebuild \
  -project "$ROOT/IoniqDrive.xcodeproj" \
  -scheme IoniqDrive \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath /tmp/ioniq-friend \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  build

APP="/tmp/ioniq-friend/Build/Products/Debug-iphoneos/IoniqDrive.app"

echo "==> Installing"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo "==> Launching"
xcrun devicectl device process launch --device "$DEVICE" com.evinfo.app || true

echo "==> Done. The app works for 7 days, then re-run this script (or enable"
echo "    automatic refresh in a sideloading tool)."
