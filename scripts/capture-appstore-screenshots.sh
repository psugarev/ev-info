#!/usr/bin/env bash
# Captures the App Store screenshot sets (6.9" and 6.5", English and Bulgarian)
# from the demo mode, without device frames or baked-in marketing text.
#
# Usage: scripts/capture-appstore-screenshots.sh
# Requires: Xcode with an iOS simulator runtime, and the app's Debug build.
#
# Output: Distribution/screenshots/{69,65}/{en,bg}/NN-name.jpg
#   01-drive  02-battery  03-cells  04-charging  05-costs  06-trip
set -euo pipefail

cd "$(dirname "$0")/.."

DERIVED="${TMPDIR:-/tmp}/evinfo-screenshots"
OUT="Distribution/screenshots"
DEVICE_69="iPhone 18 Pro Max"
DEVICE_65="iPhone 11 Pro Max"
DEVICE_65_NAME="iPhone 11 Pro Max (screenshots)"

# Drive is captured last: demo trips seed asynchronously, and the header shows
# the settled "Demo data" state instead of a transient one.
ROUTES=(battery cells charging costs trip drive)
NAMES=(02-battery 03-cells 04-charging 05-costs 06-trip 01-drive)

echo "==> Building Debug simulator app"
xcodebuild -project IoniqDrive.xcodeproj -scheme IoniqDrive -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO build >/dev/null
APP="$DERIVED/Build/Products/Debug-iphonesimulator/IoniqDrive.app"

device_id() { # find a simulator by name, creating 6.5" from its device type
  local name="$1" type="$2" existing
  existing=$(xcrun simctl list devices available | awk -v n="$name" 'index($0, n " (") {print $0; exit}')
  if [[ -n "$existing" ]]; then
    echo "$existing" | grep -oE '[0-9A-F-]{36}' | head -1
  else
    xcrun simctl create "$name" "$type"
  fi
}

D69=$(device_id "$DEVICE_69" "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max")
D65=$(device_id "$DEVICE_65_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-11-Pro-Max")

# Free simulator slots: two devices are needed and the host may already have
# others booted (macOS limits the number of user processes).
xcrun simctl shutdown all >/dev/null 2>&1 || true

for device in "$D69" "$D65"; do
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null
done

xcrun simctl status_bar "$D69" override --time "9:41" --wifiBars 3 --cellularBars 4 \
  --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true
xcrun simctl status_bar "$D65" override --time "9:41" --wifiBars 3 --cellularBars 4 \
  --batteryState charged --batteryLevel 100 >/dev/null 2>&1 || true

capture() { # device language size-dir
  local device="$1" lang="$2" size_dir="$3"
  # Fresh install per language: demo trips/summaries are written in the
  # language that was active when they were seeded.
  xcrun simctl uninstall "$device" com.evinfo.app >/dev/null 2>&1 || true
  xcrun simctl install "$device" "$APP"

  mkdir -p "$OUT/$size_dir/$lang"
  for i in "${!ROUTES[@]}"; do
    local route="${ROUTES[$i]}" name="${NAMES[$i]}" attempt=1
    # The simulator can need >15 s for a cold launch (SwiftData + demo seed),
    # and occasionally renders the launch screen white. Retry until the JPEG
    # looks like real content instead of a blank frame.
    while :; do
      local wait=15
      if [[ "$i" -eq 0 ]]; then wait=25; fi
      xcrun simctl terminate "$device" com.evinfo.app >/dev/null 2>&1 || true
      xcrun simctl launch "$device" com.evinfo.app \
        -demo -demoRoute "$route" -appLanguage "$lang" >/dev/null
      sleep "$wait"
      xcrun simctl io "$device" screenshot "/tmp/evinfo-$name.png" >/dev/null 2>&1
      sips -s format jpeg -s formatOptions 88 \
        "/tmp/evinfo-$name.png" --out "$OUT/$size_dir/$lang/$name.jpg" >/dev/null
      local bytes
      bytes=$(stat -f%z "$OUT/$size_dir/$lang/$name.jpg")
      # A blank launch screen compresses to ~30 KB; real screens are >60 KB.
      if [[ "$bytes" -gt 60000 || "$attempt" -ge 4 ]]; then break; fi
      attempt=$((attempt + 1))
      echo "    retry $attempt for $name (blank frame, ${bytes} B)"
      sleep 6
    done
    echo "    $size_dir/$lang/$name.jpg"
  done
}

echo "==> 6.9 inch (1320x2868)"
for lang in en bg; do capture "$D69" "$lang" "69"; done
echo "==> 6.5 inch (1242x2688)"
for lang in en bg; do capture "$D65" "$lang" "65"; done

echo "==> Verifying pixel sizes"
fail=0
check() { # file expected-width expected-height
  local file="$1" w h
  w=$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')
  h=$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')
  if [[ "$w" != "$2" || "$h" != "$3" ]]; then
    echo "  ✗ $file is ${w}x${h}, expected $2x$3"; fail=1
  fi
}
for f in "$OUT"/69/*/*.jpg; do check "$f" 1320 2868; done
for f in "$OUT"/65/*/*.jpg; do check "$f" 1242 2688; done
[[ "$fail" == 0 ]] && echo "    all screenshots match App Store sizes" || exit 1

echo "Done: $OUT"
