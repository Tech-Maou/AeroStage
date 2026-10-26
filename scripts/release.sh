#!/bin/bash
# Builds the release zip for GitHub and prints its SHA256 for the Homebrew cask.
# The version comes from Resources/Info.plist. If the tap is checked out next to this
# repository (../homebrew-tap, or $AEROSTAGE_TAP), its cask is updated as well.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
scripts/bundle.sh release

mkdir -p dist
ZIP="dist/AeroStage-v$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/AeroStage.app "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

echo "Release: $ZIP"
echo "Version: $VERSION"
echo "SHA256:  $SHA"

CASK="${AEROSTAGE_TAP:-../homebrew-tap}/Casks/aerostage.rb"
if [[ -f "$CASK" ]]; then
    sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
    echo "Updated $CASK"
fi
