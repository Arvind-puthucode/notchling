#!/usr/bin/env bash
# Builds Notchling.app and a drag-to-Applications DMG into ./dist.
#
#   scripts/build-dmg.sh                 # ad-hoc signed (fine for your own Mac)
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary scripts/build-dmg.sh
#
# NOTARY_PROFILE is a keychain profile made with `xcrun notarytool store-credentials`.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_ID="${SIGN_ID:--}"
ARCHS="${ARCHS:-arm64 x86_64}"

DIST="dist"
APP="$DIST/Notchling.app"
DMG="$DIST/Notchling-$VERSION.dmg"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

arch_flags=()
for a in $ARCHS; do arch_flags+=(--arch "$a"); done
echo "==> Building ($ARCHS)"
swift build -c release "${arch_flags[@]}"
BIN="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

cp "$BIN/Notchling" "$APP/Contents/MacOS/Notchling"
cp "$BIN/notchling-mcp" "$APP/Contents/MacOS/notchling-mcp"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Icon"
ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing with identity: $SIGN_ID"
sign_flags=(--force --sign "$SIGN_ID")
[[ "$SIGN_ID" != "-" ]] && sign_flags+=(--options runtime --timestamp)
codesign "${sign_flags[@]}" "$APP/Contents/MacOS/notchling-mcp"
codesign "${sign_flags[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Notchling" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
[[ "$SIGN_ID" != "-" ]] && codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"
