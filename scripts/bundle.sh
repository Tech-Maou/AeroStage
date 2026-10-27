#!/bin/bash
# Builds build/AeroStage.app from the SPM products and signs it.
# Signs with the certificate "AeroStage Dev" (or $AEROSTAGE_SIGN_IDENTITY), otherwise ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP=build/AeroStage.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/AeroStageApp" "$APP/Contents/MacOS/AeroStage"
cp "$BIN/aerostage" "$APP/Contents/Helpers/aerostage"

# App icon from Resources/Icon/AppIcon.png (drawn by scripts/make-icons.swift).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/Icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/Icon/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Signing identity: $AEROSTAGE_SIGN_IDENTITY, else "AeroStage Release" (long-lived, used for
# releases so macOS permissions survive updates), else "AeroStage Dev", else ad-hoc.
IDENTITY="${AEROSTAGE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    for candidate in "AeroStage Release" "AeroStage Dev"; do
        if security find-identity -p codesigning | grep -q "\"$candidate\""; then
            IDENTITY="$candidate"
            break
        fi
    done
fi
if [[ -z "$IDENTITY" ]] || ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "No code signing certificate found, signing ad-hoc" >&2
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier io.github.tech-maou.AeroStage.cli "$APP/Contents/Helpers/aerostage"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built: $APP (signed: $IDENTITY)"
