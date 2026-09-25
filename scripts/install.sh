#!/bin/sh
# Builds MyNotch (Release), installs it to /Applications and relaunches it.
# The installed copy registers itself as the login item on launch.
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=/Applications/MyNotch.app
BUILT="$ROOT/build/DerivedData/Build/Products/Release/MyNotch.app"

cd "$ROOT"
xcodegen generate >/dev/null
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Release \
    -derivedDataPath build/DerivedData build | grep -E "^\*\*|error:" || true
[ -d "$BUILT" ] || { echo "Build failed; nothing installed."; exit 1; }
codesign --verify --deep --strict "$BUILT"

# Quit every running copy (installed or a debug build) before replacing the app.
pkill -x MyNotch 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$BUILT" "$DEST"
open "$DEST"
echo "Installed $DEST and relaunched it."
