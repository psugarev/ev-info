#!/usr/bin/env bash
# Archives EV Info for App Store Connect / TestFlight.
#
#   scripts/archive-appstore.sh              # signed .xcarchive + version check
#   scripts/archive-appstore.sh --export     # also export a signed .ipa
#   scripts/archive-appstore.sh --dry-run    # print the plan, touch nothing
#
# Build numbers: App Store Connect needs every uploaded build to be higher than
# the previous one for the same marketing version. This script defaults the build
# number to the git commit count and lets both values be overridden:
#
#   MARKETING_VERSION=1.0 CURRENT_PROJECT_VERSION=42 scripts/archive-appstore.sh
#
# MARKETING_VERSION is the user-facing version and changes only per release train.
# Signing uses automatic provisioning; Xcode must be signed into the Apple ID that
# owns the team in project.yml (`-allowProvisioningUpdates` is passed).
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="IoniqDrive.xcodeproj"
SCHEME="IoniqDrive"
TEAM_ID="${DEVELOPMENT_TEAM:-$(awk '/DEVELOPMENT_TEAM/ {print $2; exit}' project.yml)}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
CURRENT_PROJECT_VERSION="${CURRENT_PROJECT_VERSION:-$(git rev-list --count HEAD)}"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/EVInfo-${MARKETING_VERSION}-${CURRENT_PROJECT_VERSION}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
EXPORT=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --export) EXPORT=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if $DRY_RUN; then
    printf '  $'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

echo "==> EV Info archive"
echo "    version ${MARKETING_VERSION} (build ${CURRENT_PROJECT_VERSION})"
echo "    team    ${TEAM_ID:-<from Xcode>}"
echo "    archive ${ARCHIVE_PATH}"

mkdir -p "$BUILD_DIR"

run xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive

if $DRY_RUN; then
  echo "==> dry run, nothing was built"
  exit 0
fi

APP="$ARCHIVE_PATH/Products/Applications/IoniqDrive.app"
[[ -d "$APP" ]] || { echo "archive has no app bundle: $APP" >&2; exit 1; }

echo "==> Verifying archive"
BUILT_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")
BUILT_BUILD=$(plutil -extract CFBundleVersion raw "$APP/Info.plist")
[[ "$BUILT_VERSION" == "$MARKETING_VERSION" ]] || {
  echo "version mismatch: archive has $BUILT_VERSION, expected $MARKETING_VERSION" >&2; exit 1; }
[[ "$BUILT_BUILD" == "$CURRENT_PROJECT_VERSION" ]] || {
  echo "build mismatch: archive has $BUILT_BUILD, expected $CURRENT_PROJECT_VERSION" >&2; exit 1; }
[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || {
  echo "privacy manifest missing from the archive" >&2; exit 1; }
echo "    ${BUILT_VERSION} (${BUILT_BUILD}), privacy manifest OK"

if $EXPORT; then
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>destination</key><string>export</string>
</dict>
</plist>
PLIST
  echo "==> Exporting IPA to $EXPORT_PATH"
  rm -rf "$EXPORT_PATH"
  run xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates
  echo "==> Done: $(find "$EXPORT_PATH" -name '*.ipa' -maxdepth 2 | head -1)"
fi

cat <<'NEXT'

Next:
  1. Open the archive in Xcode Organizer (Window → Organizer → Archives) or upload
     the .ipa with Transporter.app / `xcrun altool --upload-app`.
  2. In App Store Connect: paste listing copy and screenshots from
     Distribution/AppStore/ASC_CHECKLIST.md.
  3. Remember: every upload needs a higher build number (just re-run this script;
     the git commit count moves as commits land, or set CURRENT_PROJECT_VERSION=N).
NEXT
