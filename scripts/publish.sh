#!/bin/bash
# Publishes a release in one go: dev → main, tag, signed zip, GitHub release with the notes from
# CHANGELOG.md, and the updated Homebrew cask.
#
# Usage: scripts/publish.sh            (version from Resources/Info.plist)
# Needs: GitHub CLI logged in (`gh auth login`), the "AeroStage Release" signing certificate and
#        the tap checked out next to this repository (../homebrew-tap, or $AEROSTAGE_TAP).
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="Tech-Maou/AeroStage"
NAME="AeroStage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
ZIP="dist/AeroStage-v$VERSION.zip"
APP="build/AeroStage.app"
CASK="aerostage"
release_build() { AEROSTAGE_SIGN_IDENTITY="AeroStage Release" scripts/release.sh; }

source scripts/publish-common.sh
