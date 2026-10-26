#!/bin/bash
# Runs the tests. With only the Command Line Tools (no Xcode) the Swift Testing
# framework lives outside the default search paths and has to be passed explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV="$(xcode-select -p)"
FRAMEWORKS="$DEV/Library/Developer/Frameworks"
LIBS="$DEV/Library/Developer/usr/lib"
if [[ -d "$FRAMEWORKS/Testing.framework" ]]; then
    exec swift test \
        -Xswiftc -F"$FRAMEWORKS" \
        -Xlinker -F"$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$LIBS" \
        "$@"
fi
exec swift test "$@"
