#!/usr/bin/env bash
# Builds Notchling.app and a drag-to-Applications DMG into ./dist.
#
#   scripts/build-dmg.sh                 # signed with a local self-signed identity (stable, so macOS
#                                        # remembers permissions across rebuilds); SIGN_ID=- for ad-hoc
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=notary scripts/build-dmg.sh
#
# NOTARY_PROFILE is a keychain profile made with `xcrun notarytool store-credentials`.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_ID="${SIGN_ID:-local}"
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
if [[ "$SIGN_ID" == "local" ]]; then
  sign_flags=(--force --keychain "$(scripts/local-signing.sh)" --sign "Notchling Local Signing")
elif [[ "$SIGN_ID" == "-" ]]; then
  sign_flags=(--force --sign -)
else
  sign_flags=(--force --sign "$SIGN_ID" --options runtime --timestamp)
fi
codesign "${sign_flags[@]}" "$APP/Contents/MacOS/notchling-mcp"
codesign "${sign_flags[@]}" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
swift scripts/make-dmg-background.swift "$STAGE/.background/bg1x.png" 1
swift scripts/make-dmg-background.swift "$STAGE/.background/bg2x.png" 2
tiffutil -cathidpicheck "$STAGE/.background/bg1x.png" "$STAGE/.background/bg2x.png" -out "$STAGE/.background/background.tiff" >/dev/null
rm "$STAGE/.background/"bg*.png

RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname "Notchling" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')"
# Lay out the Finder window. Needs Automation permission for Finder; skipped (plain window) if denied or headless.
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "$(basename "$MOUNT")"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Notchling.app" of container window to {170, 190}
    set position of item "Applications" of container window to {470, 190}
    update without registering applications
    delay 1
    close
    open
    delay 1
    set the bounds of container window to {200, 120, 840, 548}
    delay 1
    close
  end tell
end tell
APPLESCRIPT
then echo "    Finder layout applied"; else echo "    (Finder layout skipped)"; fi
SetFile -a C "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet || hdiutil detach "$MOUNT" -force -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov >/dev/null
if [[ "$SIGN_ID" != "-" && "$SIGN_ID" != "local" ]]; then codesign --force --sign "$SIGN_ID" --timestamp "$DMG"; fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  echo "==> Notarizing"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"
