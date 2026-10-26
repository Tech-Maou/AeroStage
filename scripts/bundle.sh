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

IDENTITY="${AEROSTAGE_SIGN_IDENTITY:-AeroStage Dev}"
if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "Certificate \"$IDENTITY\" not found, signing ad-hoc" >&2
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --identifier io.github.tech-maou.AeroStage.cli "$APP/Contents/Helpers/aerostage"
codesign --force --sign "$IDENTITY" "$APP"
echo "Built: $APP (signed: $IDENTITY)"
