#!/bin/bash
# Builds AeroStage, replaces /Applications/AeroStage.app and restarts the app.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${AEROSTAGE_INSTALL_DIR:-/Applications}/AeroStage.app"
scripts/bundle.sh release

if pgrep -xq AeroStage; then
    "$TARGET/Contents/Helpers/aerostage" quit 2>/dev/null || pkill -x AeroStage || true
    sleep 0.5
fi
rm -rf "$TARGET"
ditto build/AeroStage.app "$TARGET"
open "$TARGET"
echo "Installed: $TARGET"
echo "CLI: $TARGET/Contents/Helpers/aerostage"
