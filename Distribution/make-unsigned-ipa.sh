#!/usr/bin/env bash
# Rebuild the unsigned Release IPA that friends sign with their own free Apple ID.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/ioniq-unsigned}"
OUT="${OUT:-$ROOT/Distribution}"
mkdir -p "$OUT"

echo "==> Building unsigned Release app"
xcodebuild \
  -project "$ROOT/IoniqDrive.xcodeproj" \
  -scheme IoniqDrive \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/IoniqDrive.app"
if [ ! -d "$APP" ]; then
  echo "error: built app not found at $APP" >&2
  exit 1
fi

# Sideloadly/AltStore add their own signature; leftover signature data would only confuse them.
rm -rf "$APP/_CodeSignature" "$APP/embedded.mobileprovision"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Payload"
cp -R "$APP" "$WORK/Payload/"
( cd "$WORK" && zip -qry "$OUT/EVInfo-unsigned.ipa" Payload )

echo "==> Wrote $OUT/EVInfo-unsigned.ipa"
ls -lh "$OUT/EVInfo-unsigned.ipa"
echo "==> Signature state (expected: not signed)"
codesign -dv "$APP" 2>&1 | head -2 || true
